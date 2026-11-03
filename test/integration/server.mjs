import express from 'express';
import { createMemoryVigilSink, vigilErrorHandler, vigilIngestHandler, vigilMiddleware } from '@vigiljs/express';

const app = express();
const sink = createMemoryVigilSink();
app.use(express.json());
app.post('/vigil/ingest', vigilIngestHandler({
  enabled: true,
  ingestKey: 'ingest-secret',
  onBatch: sink.onBatch,
}));
app.get('/batches', (_req, res) => res.json(sink.batches));
app.use(vigilMiddleware({ enabled: true, debugKey: 'debug-secret' }));
app.all('/ok', async (req, res) => {
  await req.vigil.time('db', 'Load result', () => Promise.resolve());
  res.json({ ok: true });
});
app.get('/error', () => {
  throw new Error('Backend failure');
});
app.use(vigilErrorHandler({ enabled: true, debugKey: 'debug-secret' }));

const server = app.listen(0, '127.0.0.1', () => {
  process.stdout.write(`${JSON.stringify({ port: server.address().port })}\n`);
});
