import express from 'express';
import { createMemoryVigilSink, vigilErrorHandler, vigilIngestHandler, vigilInspectorRouter, vigilMiddleware, VigilFailureSimulation } from '@vigiljs/express';

const app = express();
const sink = createMemoryVigilSink();
const simulation = new VigilFailureSimulation({
  enabled: true, debugKey: 'debug-secret', controlKey: 'control-secret',
  allowedPaths: ['/ok', '/error'],
});
app.use(express.json());
app.post('/vigil/ingest', vigilIngestHandler({
  enabled: true,
  ingestKey: 'ingest-secret',
  onBatch: sink.onBatch,
}));
app.use('/vigil/inspector', vigilInspectorRouter({ sink, simulation, readKey: 'read-secret', enabled: true }));
app.get('/batches', (_req, res) => res.json(sink.batches));
app.use(vigilMiddleware({ enabled: true, debugKey: 'debug-secret' }));
app.use(simulation.middleware());
app.all('/ok', async (req, res) => {
  await req.vigil.time('db', 'Load result', () => Promise.resolve());
  req.vigil.log('info', 'Loaded result', { count: 1 });
  res.json({ ok: true });
});
app.get('/error', (req) => {
  req.vigil.log('warn', 'Result missing');
  throw new Error('Backend failure');
});
app.use(vigilErrorHandler({ enabled: true, debugKey: 'debug-secret' }));

const server = app.listen(0, '127.0.0.1', () => {
  process.stdout.write(`${JSON.stringify({ port: server.address().port })}\n`);
});
