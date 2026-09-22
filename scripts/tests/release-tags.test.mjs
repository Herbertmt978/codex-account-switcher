import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { validateReleaseTag } from '../validate-release-tag.mjs';

test('one tag must match both platform versions and all package metadata', () => {
  const version = fs.readFileSync('CITATION.cff', 'utf8').match(/^version:\s*(\S+)/m)[1];
  assert.equal(validateReleaseTag(`v${version}`), version);
  for (const tag of [`macos-v${version}`, `windows-v${version}`, 'v01.1.0', 'v0.1', 'v0.1.0-rc1', 'v999.0.0']) {
    assert.throws(() => validateReleaseTag(tag));
  }
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'switcher-version-'));
  try {
    for (const file of ['CITATION.cff', 'scripts/package-local-app.sh', 'Sources/SwitcherCore/CodexClient.swift', 'windows/Directory.Build.props']) {
      fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
      fs.copyFileSync(file, path.join(root, file));
    }
    const props = path.join(root, 'windows/Directory.Build.props');
    fs.writeFileSync(props, fs.readFileSync(props, 'utf8').replace(`<Version>${version}</Version>`, '<Version>999.0.0</Version>'));
    assert.throws(() => validateReleaseTag(`v${version}`, root), /unified version sources/);
  } finally { fs.rmSync(root, { recursive: true }); }
});

test('publication waits for both builds and only the unified workflow publishes', () => {
  const release = fs.readFileSync('.github/workflows/release.yml', 'utf8');
  const windows = fs.readFileSync('.github/workflows/windows.yml', 'utf8');
  assert.match(release, /tags:\s*\n\s*- "v\*"/);
  assert.match(release, /needs: \[validate, macos, windows\]/);
  assert.match(release, /verify-release-artifacts\.mjs/);
  assert.match(release, /--draft --verify-tag/);
  assert.match(release, /--draft=false --latest/);
  assert.match(windows, /workflow_call:/);
  assert.doesNotMatch(windows, /gh release create|tags:/);
});

test('fork releases wait for both verified packages and remain separate from upstream signing', () => {
  const fork = fs.readFileSync('.github/workflows/fork-release.yml', 'utf8');
  const upstream = fs.readFileSync('.github/workflows/release.yml', 'utf8');
  const packaging = fs.readFileSync('scripts/package-fork-macos.sh', 'utf8');
  assert.match(fork, /if: github.repository == 'Herbertmt978\/codex-account-switcher'/);
  assert.match(upstream, /if: github.repository == 'liuzhao1225\/codex-account-switcher'/);
  assert.match(fork, /needs: \[validate, macos, windows\]/);
  assert.match(fork, /verify-release-artifacts\.mjs dist "\$GITHUB_REF_NAME" fork/);
  assert.match(fork, /--draft --verify-tag/);
  assert.match(fork, /--draft=false --latest/);
  assert.match(packaging, /codesign --verify --deep --strict "\$mounted_app"/);
  assert.match(packaging, /SwitcherReleasePage/);
  assert.match(packaging, /kill -0 "\$app_pid"/);
});

test('upstream website metadata checks do not gate the fork release version', () => {
  const ci = fs.readFileSync('.github/workflows/ci.yml', 'utf8');
  const pages = fs.readFileSync('.github/workflows/pages.yml', 'utf8');
  assert.match(ci, /name: Check SEO and GEO consistency\s+if: github\.repository == 'liuzhao1225\/codex-account-switcher'/);
  assert.match(pages, /github\.repository == 'liuzhao1225\/codex-account-switcher'/);
});
