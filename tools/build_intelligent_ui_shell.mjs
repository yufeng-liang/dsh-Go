#!/usr/bin/env node
// 将 renderer.js 重新内联进 shell.html，保留 shell 的样式与 host 桥接。
import { readFile, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const asset = resolve(root, 'app/assets/intelligent_ui')
const rendererPath = resolve(asset, 'renderer.js')
const shellPath = resolve(asset, 'shell.html')

const renderer = await readFile(rendererPath, 'utf8')
const shell = await readFile(shellPath, 'utf8')
const startMarker = '<script>"use strict";var DshIntelligentUiRenderer='
const endMarker = /<\/script>\r?\n<script>\r?\n\(function\(\)\{/
if (!renderer.startsWith('"use strict";var DshIntelligentUiRenderer=')) {
  throw new Error('renderer.js does not start with the expected IIFE header')
}
if (renderer.includes('</script>')) throw new Error('renderer.js contains a literal </script>')
const start = shell.indexOf(startMarker)
const endMatch = start < 0 ? null : endMarker.exec(shell.slice(start))
if (start < 0 || !endMatch) throw new Error('shell.html renderer markers not found')
const newline = shell.includes('\r\n') ? '\r\n' : '\n'
const before = shell.slice(0, start)
const after = shell.slice(start + endMatch.index + endMatch[0].length)
const next = `${before}<script>${renderer.trimEnd()}</script>${newline}<script>${newline}(function(){${after}`
await writeFile(shellPath, next, 'utf8')
console.log(JSON.stringify({ rendererBytes: Buffer.byteLength(renderer), shellBytes: Buffer.byteLength(next), embeddedBytes: Buffer.byteLength(next) - Buffer.byteLength(before) - Buffer.byteLength(after) - '<script></script>'.length }))
