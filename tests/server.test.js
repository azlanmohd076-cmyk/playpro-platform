import test, { after, before } from 'node:test'
import assert from 'node:assert/strict'

process.env.NODE_ENV = 'test'
const { server } = await import('../server.mjs')
let base

before(async () => {
  await new Promise((resolve, reject) => {
    server.once('error', reject)
    server.listen(0, '127.0.0.1', resolve)
  })
  base = `http://127.0.0.1:${server.address().port}`
})

after(async () => {
  await new Promise(resolve => server.close(resolve))
})

test('serves canonical deployed JS and security headers', async () => {
  const response = await fetch(`${base}/js/repositories.js`)
  assert.equal(response.status, 200)
  assert.equal(response.headers.get('x-content-type-options'), 'nosniff')
  assert.match(await response.text(), /window\.ProfileRepo/)
})

test('supports HEAD and rejects unsupported methods', async () => {
  const head = await fetch(`${base}/`, { method: 'HEAD' })
  assert.equal(head.status, 200)
  assert.equal(await head.text(), '')
  const post = await fetch(`${base}/`, { method: 'POST' })
  assert.equal(post.status, 405)
  assert.equal(post.headers.get('allow'), 'GET, HEAD')
})

test('does not expose files outside public', async () => {
  const response = await fetch(`${base}/..%2Fpackage.json`)
  assert.ok([400, 404].includes(response.status))
})
