import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { verifyReleaseArtifacts } from '../verify-release-artifacts.mjs';

test('fork publication requires both intact packages without an upstream update feed', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'switcher-fork-assets-'));
  const packages = ['Codex-Account-Switcher-windows-x64.exe', 'Codex-Account-Switcher-macos-arm64.dmg'];
  try {
    for (const name of packages) {
      await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3', 'fork'), /ENOENT/);
      await fs.writeFile(path.join(dir, name), name);
      await fs.writeFile(path.join(dir, name + '.sha256'), createHash('sha256').update(name).digest('hex') + '  ' + name + '\n');
    }
    await verifyReleaseArtifacts(dir, 'v1.2.3', 'fork');
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3'), /ENOENT/);
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3', 'unknown'), /Unknown release platform/);
    for (const name of packages) {
      await fs.writeFile(path.join(dir, name), 'corrupt');
      await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3', 'fork'), /Checksum mismatch/);
      await fs.writeFile(path.join(dir, name), name);
    }
  } finally { await fs.rm(dir, { recursive: true }); }
});

test('publishing requires both intact packages and a matching signed feed', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'switcher-assets-'));
  const mac = 'Codex-Account-Switcher-macos-arm64.dmg';
  const win = 'Codex-Account-Switcher-windows-x64.exe';
  try {
    for (const name of [mac, win]) {
      await fs.writeFile(path.join(dir, name), name);
      await fs.writeFile(path.join(dir, name + '.sha256'), createHash('sha256').update(name).digest('hex') + '  ' + name + '\n');
    }
    const xml = `<rss><sparkle:shortVersionString>1.2.3</sparkle:shortVersionString><enclosure url="https://github.com/liuzhao1225/codex-account-switcher/releases/download/v1.2.3/${mac}" sparkle:edSignature="fixture" /></rss>`;
    await fs.writeFile(path.join(dir, 'appcast.xml'), xml);
    await verifyReleaseArtifacts(dir, 'v1.2.3');
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.4'));
    await fs.writeFile(path.join(dir, 'appcast.xml'), xml.replace('>1.2.3<', '>1.2.2<'));
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3'), /version differs/);
    await fs.writeFile(path.join(dir, 'appcast.xml'), xml);
    await fs.writeFile(path.join(dir, win), 'corrupt');
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3'), /Checksum mismatch/);
    await fs.unlink(path.join(dir, win));
    await assert.rejects(verifyReleaseArtifacts(dir, 'v1.2.3'), /ENOENT/);
  } finally { await fs.rm(dir, { recursive: true }); }
});
