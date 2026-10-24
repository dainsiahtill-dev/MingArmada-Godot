// The two published story structures are explicit contracts. New data must not
// silently redefine its own expected counts or orphan previously shared links.
export const legacySceneIds = Object.freeze([
  ...Array.from({ length: 6 }, (_, i) => `zheng_a1_s${i + 1}`),
  ...Array.from({ length: 8 }, (_, i) => `zheng_a2_s${i + 1}`),
  ...Array.from({ length: 10 }, (_, i) => `zheng_a3_s${i + 1}`),
  ...Array.from({ length: 7 }, (_, i) => `zheng_a4_s${i + 1}`),
  ...Array.from({ length: 7 }, (_, i) => `zheng_a5_s${i + 1}`),
  ...Array.from({ length: 5 }, (_, i) => `zheng_a6_s${i + 1}`),
]);

export function storyStructure(story) {
  const contract = story?.narrativeContract;
  if (contract === undefined) return { edition: 'legacy-six-act', acts: 6, scenesPerAct: null, sceneCount: null, prefix: 'zheng' };
  if (!contract || contract.acts !== 5 || contract.scenesPerAct !== 4 || contract.canonicalPrefix !== 'yiguan') {
    throw new Error('New narrativeContract must explicitly be five acts, four scenes per act, canonicalPrefix=yiguan.');
  }
  return { edition: 'five-act-rewrite', acts: 5, scenesPerAct: 4, sceneCount: 20, prefix: 'yiguan' };
}

export function aliasIssues(story) {
  const structure = storyStructure(story);
  if (structure.edition !== 'five-act-rewrite') return [];
  const issues = [], aliases = story.legacySceneAliases;
  if (!aliases || typeof aliases !== 'object' || Array.isArray(aliases)) return ['legacySceneAliases must map all 43 published scene IDs.'];
  const canonical = new Set((story.acts || []).flatMap(act => act.scenes || []).map(scene => scene.id));
  for (const id of legacySceneIds) if (!Object.hasOwn(aliases, id)) issues.push(`Missing published scene alias: ${id}`);
  for (const [from, to] of Object.entries(aliases)) {
    if (!legacySceneIds.includes(from)) issues.push(`Unknown published scene alias: ${from}`);
    if (!canonical.has(to)) issues.push(`Alias ${from} points outside current scenes: ${to}`);
    if (Object.hasOwn(aliases, to)) issues.push(`Alias chains are not allowed: ${from}`);
  }
  return issues;
}
