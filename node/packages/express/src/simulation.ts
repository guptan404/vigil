import { isVigilSessionId } from "./sessions.js";
import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import type { Request, RequestHandler } from "express";

export type VigilFailureEffect = "httpError" | "exception" | "delay" | "timeout" | "disconnect";

export interface VigilFailureRuleInput {
  method: string;
  /** Exact path, without a query string. Must be in allowedPaths. */
  path: string;
  effect: VigilFailureEffect;
  /** Limit this rule to one frontend session. Omit for an explicit global rule. */
  sessionId?: string;
  /** Registered point inside application code. Omit for request-entry rules. */
  failurePoint?: string;
  statusCode?: number;
  body?: unknown;
  /** Server delay in milliseconds. A timeout closes the socket after this delay. */
  delayMs?: number;
  /** Omit to keep the rule active until removed. */
  times?: number;
}

export interface VigilFailureRule {
  readonly id: string;
  readonly method: string;
  readonly path: string;
  readonly effect: VigilFailureEffect;
  readonly sessionId?: string;
  readonly failurePoint?: string;
  readonly statusCode: number;
  readonly body: unknown;
  readonly delayMs: number;
  readonly remaining: number | null;
}

export interface VigilFailureSimulationConfig {
  /** Requests must carry the development Vigil-Key to be affected. */
  debugKey: string;
  /** A separate server-only key for creating and deleting rules. */
  controlKey: string;
  /** Exact application endpoints that may be simulated. */
  allowedPaths: readonly string[];
  /** Named operations and factories for the real errors those operations throw. */
  failurePoints?: Readonly<Record<string, () => Error>>;
  /** Defaults to enabled outside production. */
  enabled?: boolean;
}

/** Development rules shared by the application middleware and inspector router. */
export class VigilFailureSimulation {
  private readonly rules = new Map<string, VigilFailureRule>();
  private readonly paths: Set<string>;
  private readonly points: Map<string, () => Error>;
  private readonly debugHash: Buffer;
  private readonly controlHash: Buffer;
  private readonly config: VigilFailureSimulationConfig;

  constructor(config: VigilFailureSimulationConfig) {
    if (!config.debugKey.trim() || !config.controlKey.trim() ||
        config.debugKey === config.controlKey) {
      throw new Error("Simulation needs distinct debug and control keys.");
    }
    if (config.allowedPaths.length === 0 || config.allowedPaths.some(path => !validPath(path))) {
      throw new Error("Simulation needs at least one exact application path.");
    }
    this.config = { ...config };
    this.paths = new Set(config.allowedPaths);
    this.points = new Map(Object.entries(config.failurePoints ?? {}));
    if ([...this.points].some(([name, factory]) => !name.trim() || typeof factory !== "function")) {
      throw new Error("Failure points need a name and an error factory.");
    }
    this.debugHash = hash(config.debugKey);
    this.controlHash = hash(config.controlKey);
  }

  get enabled(): boolean {
    return this.config.enabled ?? process.env.NODE_ENV !== "production";
  }

  get allowedPaths(): readonly string[] {
    return [...this.paths];
  }

  get failurePoints(): readonly string[] {
    return [...this.points.keys()];
  }

  /** Throws the registered application error only when a matching rule is armed. */
  failPoint(req: Request, name: string): void {
    const rule = this.takeRule(req, name);
    if (!rule) return;
    req.vigil?.log("warn", "Vigil code failure simulation", {
      ruleId: rule.id, failurePoint: name, path: rule.path, sessionId: rule.sessionId,
    });
    const error = this.points.get(name)!();
    if (!(error instanceof Error)) throw new TypeError("Failure point factory must return an Error.");
    throw error;
  }

  authorizeControl(key: string | undefined): boolean {
    return this.enabled && timingSafeEqual(hash(key ?? ""), this.controlHash);
  }

  list(): readonly VigilFailureRule[] {
    return [...this.rules.values()].map(rule => structuredClone(rule));
  }

  /** Validates before atomically replacing the rule for a method and path. */
  put(input: VigilFailureRuleInput): VigilFailureRule {
    if (!this.enabled) throw new Error("Failure simulation is disabled.");
    const rule = this.parseRule(input);
    const previous = [...this.rules.values()].find(
      item => item.method === rule.method && item.path === rule.path &&
        item.failurePoint === rule.failurePoint && item.sessionId === rule.sessionId,
    );
    if (!previous && this.rules.size >= 100) throw new Error("At most 100 failure rules are allowed.");
    if (previous) this.rules.delete(previous.id);
    this.rules.set(rule.id, rule);
    return structuredClone(rule);
  }

  remove(id: string): boolean {
    return this.rules.delete(id);
  }

  clear(sessionId?: string): void {
    if (sessionId === undefined) {
      this.rules.clear();
      return;
    }
    for (const [id, rule] of this.rules) {
      if (rule.sessionId === sessionId) this.rules.delete(id);
    }
  }

  /** Mount after vigilMiddleware and before the application routes. */
  middleware(): RequestHandler {
    return (req, res, next) => {
      const rule = this.takeRule(req);
      if (!rule) {
        next();
        return;
      }
      req.vigil?.log("warn", "Vigil server failure simulation", {
        ruleId: rule.id, effect: rule.effect, path: rule.path, sessionId: rule.sessionId,
      });
      res.setHeader("Vigil-Simulation", rule.effect);
      const apply = () => {
        if (res.destroyed || res.writableEnded) return;
        switch (rule.effect) {
          case "httpError":
            res.status(rule.statusCode).json(structuredClone(rule.body));
            break;
          case "exception":
            next(Object.assign(new Error("Vigil simulated backend exception"), {
              status: rule.statusCode,
            }));
            break;
          case "delay":
            next();
            break;
          case "timeout":
          case "disconnect":
            res.destroy();
            break;
        }
      };
      if (rule.delayMs === 0) {
        apply();
        return;
      }
      const timer = setTimeout(() => {
        res.off("close", cancel);
        apply();
      }, rule.delayMs);
      const cancel = () => clearTimeout(timer);
      res.once("close", cancel);
    };
  }

  private takeRule(req: Request, failurePoint?: string): VigilFailureRule | undefined {
    if (!this.enabled || req.method === "OPTIONS" ||
        !timingSafeEqual(hash(req.header("Vigil-Key") ?? ""), this.debugHash)) {
      return undefined;
    }
    const sessionId = req.header("Vigil-Session-Id");
    const matching = [...this.rules.values()].filter(
      item => item.method === req.method && item.path === req.path &&
        item.failurePoint === failurePoint,
    );
    // A device rule wins over an explicitly configured global rule.
    const rule = (isVigilSessionId(sessionId)
      ? matching.find(item => item.sessionId === sessionId) : undefined) ??
      matching.find(item => item.sessionId === undefined);
    // Consume before entering application code so concurrent calls respect times.
    if (rule && rule.remaining !== null) {
      if (rule.remaining === 1) this.rules.delete(rule.id);
      else this.rules.set(rule.id, { ...rule, remaining: rule.remaining - 1 });
    }
    return rule;
  }

  private parseRule(input: VigilFailureRuleInput): VigilFailureRule {
    if (!input || typeof input !== "object" || Array.isArray(input)) {
      throw new Error("Enter a failure rule.");
    }
    if (typeof input.method !== "string" || !/^[A-Z]+$/.test(input.method) ||
        input.method === "OPTIONS" || !this.paths.has(input.path)) {
      throw new Error("Choose an HTTP method and an allowed exact path.");
    }
    const effects: VigilFailureEffect[] = ["httpError", "exception", "delay", "timeout", "disconnect"];
    if (!effects.includes(input.effect)) throw new Error("Choose a supported failure effect.");
    if (input.failurePoint !== undefined &&
        (typeof input.failurePoint !== "string" || !this.points.has(input.failurePoint) ||
         input.effect !== "exception" || (input.delayMs ?? 0) !== 0 ||
         input.statusCode !== undefined || input.body !== undefined)) {
      throw new Error("Code failure points use a registered error factory. Choose exception and omit status, body and delay.");
    }
    if (input.sessionId !== undefined && !isVigilSessionId(input.sessionId)) {
      throw new Error("Enter a valid frontend session ID.");
    }
    const statusCode = input.statusCode ?? 500;
    const delayMs = input.delayMs ?? (input.effect === "timeout" ? 30000 : 0);
    if (!Number.isInteger(statusCode) || statusCode < 400 || statusCode > 599) {
      throw new Error("Error status must be between 400 and 599.");
    }
    if (!Number.isInteger(delayMs) || delayMs < 0 || delayMs > 120000 ||
        (["delay", "timeout"].includes(input.effect) && delayMs === 0)) {
      throw new Error("Delay must be between 1 and 120000 ms for a delay or timeout.");
    }
    if (input.times !== undefined && (!Number.isInteger(input.times) || input.times < 1 || input.times > 10000)) {
      throw new Error("Request count must be between 1 and 10000, or omitted.");
    }
    const encoded = JSON.stringify(input.body === undefined ? { error: "Vigil simulated failure" } : input.body);
    if (encoded === undefined || Buffer.byteLength(encoded) > 64 * 1024) {
      throw new Error("JSON body must be at most 64 KiB.");
    }
    return Object.freeze({
      id: randomUUID(), method: input.method, path: input.path, effect: input.effect,
      statusCode, body: JSON.parse(encoded), delayMs, remaining: input.times ?? null,
      ...(input.failurePoint === undefined ? {} : { failurePoint: input.failurePoint }),
      ...(input.sessionId === undefined ? {} : { sessionId: input.sessionId }),
    });
  }
}

function hash(value: string): Buffer {
  return createHash("sha256").update(value).digest();
}

function validPath(path: unknown): path is string {
  return typeof path === "string" && path.startsWith("/") &&
    !path.includes("?") && !path.includes("#") && path !== "/vigil" && !path.startsWith("/vigil/");
}
