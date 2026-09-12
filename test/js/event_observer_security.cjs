'use strict';
const assert = require('node:assert/strict');
const vm = require('node:vm');
const script = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
const cap = 4194304;

function make({origin = 'https://zcode.z.ai', frame = false, bridge = true, fetch} = {}) {
  const calls = [], listeners = {};
  let decodes = 0;
  class Socket {
    constructor() { this.listeners = {}; }
    addEventListener(name, callback) { this.listeners[name] = callback; }
    message(data) { this.listeners.message({data}); }
  }
  const window = {
    location: {origin}, WebSocket: Socket, EventSource: Socket,
    fetch,
    addEventListener(name, callback) { listeners[name] = callback; },
  };
  window.top = frame ? {} : window;
  const installBridge = () => {
    window.flutter_inappwebview = {
      callHandler(...args) { calls.push(args); return Promise.resolve(null); },
    };
  };
  if (bridge) installBridge();
  const context = vm.createContext({window, TextDecoder, Uint8Array,
    atob(value) { decodes++; return atob(value); },
    setInterval() { return 1; }, clearInterval() {},
  });
  vm.runInContext(script, context);
  return {window, calls, listeners, installBridge,
    socket: () => new window.WebSocket('wss://zcode.z.ai/ws'),
    decodes: () => decodes};
}

for (const options of [{origin: 'https://evil.example'}, {frame: true}]) {
  const env = make(options);
  assert.equal(env.window.__zrHooked, undefined);
  assert.equal(env.calls.length, 0);
}

{
  const env = make(), socket = env.socket();
  const body = JSON.stringify({event: 'completed'});
  socket.message(body);
  assert.deepEqual(env.calls, [['zrEvents', 'test-nonce', body]]);
  socket.message('x'.repeat(cap + 1));
  socket.message('中'.repeat(Math.floor(cap / 3) + 1));
  assert.equal(env.calls.length, 1, 'oversized strings must never cross the bridge');
}

{
  const env = make({bridge: false}), socket = env.socket();
  for (let i = 0; i < 3000; i++) socket.message(JSON.stringify({i}));
  env.installBridge();
  env.listeners.flutterInAppWebViewPlatformReady();
  assert.equal(env.calls.length, 2048);
  assert.equal(JSON.parse(env.calls[0][2]).i, 952);
}

function fragment(socket, {id = 'frame', index, count, text}) {
  socket.message(JSON.stringify({payload: {kind: 'fragment', logicalFrameId: id,
    fragmentIndex: index, fragmentCount: count, messageBytes: 1,
    dataBase64: Buffer.from(text).toString('base64')}}));
}

{
  const env = make(), socket = env.socket();
  fragment(socket, {index: 0, count: 2, text: '{"event":'});
  fragment(socket, {index: 0, count: 2, text: 'ignored duplicate'});
  fragment(socket, {index: 1, count: 2, text: '"completed"}'});
  assert.equal(env.decodes(), 2, 'duplicate chunks must not allocate new byte buffers');
  assert.equal(env.calls.at(-1)[2], '{"event":"completed"}');
}

{
  const env = make(), socket = env.socket();
  for (const count of [0, -1, 1025, Infinity, 2.5]) {
    fragment(socket, {index: 0, count, text: 'bad'});
  }
  fragment(socket, {index: -1, count: 2, text: 'bad'});
  fragment(socket, {index: 2, count: 2, text: 'bad'});
  assert.equal(env.decodes(), 0, 'invalid metadata rejected before base64 allocation');
  socket.message(JSON.stringify({payload: {messageBytes: 1,
    dataBase64: 'A'.repeat(cap + 4)}}));
  assert.equal(env.decodes(), 0, 'forged size hints cannot bypass the actual-size cap');
}

{
  const env = make(), socket = env.socket();
  const piece = 'a'.repeat(cap / 2);
  for (let i = 0; i < 3; i++) fragment(socket, {index: i, count: 3, text: piece});
  assert.equal(env.calls.length, 3, 'over-limit assemblies never produce decoded messages');
  fragment(socket, {id: '__proto__', index: 0, count: 1, text: '{"event":"error"}'});
  assert.equal(env.calls.at(-1)[2], '{"event":"error"}', 'fragment ids cannot mutate prototypes');
}

async function streamChecks() {
  let cancels = 0, replies = [];
  const env = make({fetch: async () => replies.shift()});
  function response(chunks) {
    const reader = {
      async read() { return chunks.length ? {done: false, value: chunks.shift()} : {done: true}; },
      async cancel() { cancels++; }, releaseLock() {},
    };
    const res = {status: 200, headers: {get() { return null; }},
      body: {getReader() { return reader; }}};
    res.clone = () => res;
    return res;
  }
  const tick = () => new Promise(resolve => setImmediate(resolve));
  const bytes = new TextEncoder().encode('{"event":"完成"}');
  replies.push(response([bytes.slice(0, 11), bytes.slice(11)]));
  await env.window.fetch('/state'); await tick();
  assert.equal(env.calls.at(-1)[2], '{"event":"完成"}', 'UTF-8 split chunks decode correctly');
  const before = env.calls.length;
  replies.push(response([new Uint8Array(cap), new Uint8Array(1)]));
  await env.window.fetch('/oversize'); await tick();
  assert.equal(env.calls.length, before);
  assert.equal(cancels, 1, 'oversized stream is cancelled before posting');
  for (let i = 0; i < 5; i++) {
    const broken = response([]);
    broken.clone = () => { throw new Error('clone failed'); };
    replies.push(broken);
    await env.window.fetch('/broken');
  }
  replies.push(response([bytes]));
  await env.window.fetch('/recovered'); await tick();
  assert.equal(env.calls.length, before + 1, 'failed clones do not exhaust read slots');
}
streamChecks().then(() => {
  process.stdout.write('JavaScript security regression checks passed.\n');
}).catch(error => { console.error(error); process.exitCode = 1; });
