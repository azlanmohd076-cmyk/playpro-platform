import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const pairs = [
  ['js/supabase.js', 'public/js/supabase.js'],
  ['js/repositories.js', 'public/js/repositories.js'],
  ['src/core/supabase-client.js', 'public/src/core/supabase-client.js'],
  ['src/modules/auth/auth-session.service.js', 'public/src/modules/auth/auth-session.service.js'],
]

test('source and deployed browser copies remain identical', async () => {
  for (const [source, deployed] of pairs) {
    const [a, b] = await Promise.all([readFile(source, 'utf8'), readFile(deployed, 'utf8')])
    assert.equal(b, a, `${deployed} drifted from ${source}`)
  }
})

test('player onboarding uses the atomic RPC and surfaces errors', async () => {
  const html = await readFile('public/index.html', 'utf8')
  const start = html.indexOf('async function obComplete(){')
  const end = html.indexOf('/* ── CLUB HISTORY ONBOARDING ── */', start)
  assert.ok(start > -1 && end > start)
  const onboarding = html.slice(start, end)
  assert.match(onboarding, /rpc\('register_my_player'/)
  assert.doesNotMatch(onboarding, /from\('players'\)\.insert/)
  assert.match(onboarding, /if\(playerResult\.error\) throw playerResult\.error/)
})
