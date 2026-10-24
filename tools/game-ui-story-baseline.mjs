// The 72-page UI is an explicitly versioned simulation. A literary rewrite
// must not silently rewrite its 236 behavioral fixtures or masquerade as game
// integration. Keep the source immutable and validate old-reader successors.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {storyStructure,aliasIssues,legacySceneIds} from './zheng-story-contract.mjs';

export const uiStoryBaselinePath='docs/narrative/rewrites/baseline-v4-2026-10-22/story.json';
export const uiStoryBaselineSha256='29e7de2c9308548b37293630530a5f3f84187862ee290629dcd80eda5826e801';
export function loadGameUiStory(root){
 const current=JSON.parse(fs.readFileSync(path.join(root,'docs/narrative/zheng-zhilong-story.json'),'utf8'));
 if(storyStructure(current).edition!=='five-act-rewrite')return current;
 const issues=aliasIssues(current);
 if(issues.length)throw new Error('UI reader successor contract invalid: '+issues.join('; '));
 const bytes=fs.readFileSync(path.join(root,uiStoryBaselinePath));
 if(crypto.createHash('sha256').update(bytes).digest('hex')!==uiStoryBaselineSha256)throw new Error('The frozen UI story source hash changed; re-audit the 236 state fixtures.');
 const baseline=JSON.parse(bytes),ids=baseline.acts.flatMap(act=>act.scenes.map(scene=>scene.id));
 if(baseline.version!=='v4-maritime-illustrated-2026-10-22'||baseline.acts.length!==6||ids.length!==43||legacySceneIds.some(id=>!ids.includes(id)))throw new Error('The UI story baseline must retain the exact published six-act, 43-scene contract.');
 return baseline;
}
