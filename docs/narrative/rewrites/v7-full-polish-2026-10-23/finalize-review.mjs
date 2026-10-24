import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(here,'../../../..');
const read=p=>fs.readFileSync(path.join(root,p));
const hash=p=>crypto.createHash('sha256').update(read(p)).digest('hex');
const source='docs/narrative/zheng-zhilong-story.json';
const receiptPath='docs/research/evidence/yiguan-full-polish-2026-10-23/browser-checks.json';
const receipt=JSON.parse(read(receiptPath));
for(const input of receipt.inputs)if(hash(input.path)!==input.sha256)throw Error(`Stale browser input ${input.path}`);
const sourceSha256=hash(source);
if(sourceSha256!=='7fc5969a5620718364e862ebf1333e9fa191bc9e8ed5351c7a866f72f5ff48f5')throw Error('Source changed after reading');
if(!read(source).equals(read('docs/narrative/zheng-zhilong/zheng-zhilong-story.json')))throw Error('Mirror differs');
const story=JSON.parse(read(source)),scenes=story.acts.flatMap(a=>a.scenes);
const metrics={paragraphs:scenes.reduce((n,s)=>n+s.paragraphs.length,0),characters:scenes.reduce((n,s)=>n+s.paragraphs.join('').length,0),dialogue:scenes.reduce((n,s)=>n+s.dialogue.length,0)};
if(metrics.paragraphs!==291||metrics.characters!==26876||metrics.dialogue!==95)throw Error('Final metrics changed');
const checks=JSON.parse(read('docs/research/evidence/yiguan-full-polish-2026-10-23/static-checks.json'));
if(checks.sourceSha256!==sourceSha256||checks.checks.length!==5||checks.checks.some(c=>c.exit_code!==0))throw Error('Static verification incomplete');
const self=receipt.selfCheck.map(x=>x.message).find(x=>x.startsWith('ZHENG_READER_SELF_CHECK '));
if(!self||!JSON.parse(self.slice('ZHENG_READER_SELF_CHECK '.length)).passed||receipt.console.length)throw Error('Browser self-check incomplete');
const expected={exactSourceScenes:20,bodyCharacters:26876,sourceParagraphs:291,processFrames:8,desktopSceneLinks:20,chapterTurnLinks:4,legacyLinks:43};
for(const [k,v]of Object.entries(expected))if(receipt.results[k]!==v)throw Error(`Missing browser result ${k}`);
const cold=read('docs/narrative/rewrites/v7-full-polish-2026-10-23/COLD-READ.md').toString('utf8');
if(!cold.includes(sourceSha256)||!cold.includes('无未关闭的阻塞项'))throw Error('Independent review missing');
const reportPath='docs/narrative/zheng-zhilong/verification.json';
const report=JSON.parse(read(reportPath));
if(!report.valid||report.summary.failed||report.illustrationValidation.needsRedraw.length)throw Error('Strict story verification failed');
report.browserValidation={status:'partial',performedAt:receipt.date,scope:receipt.scope,focusedNarrativeChecks:'passed',evidence:receiptPath,
 report:'docs/research/evidence/yiguan-full-polish-2026-10-23/REVIEW.md',inputs:receipt.inputs,notRetested:receipt.notRetested,
 note:'Current 20-scene content, all 43 old links, chapter turns, responsive samples and reader self-check passed in the real browser; native platform checks remain partial.'};
report.editorialReview={status:'reviewed-after-full-polish',sourceSha256,report:'docs/narrative/rewrites/v7-full-polish-2026-10-23/EDITING-REPORT.md',
 independentReview:'docs/narrative/rewrites/v7-full-polish-2026-10-23/COLD-READ.md',metrics,
 note:'Seventeen remaining scenes revised; three prior focus bodies preserved. Full draft read independently, then eight precise coordinated edits rechecked. No publication or player-retention certification.'};
fs.writeFileSync(path.join(root,reportPath),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({strict:report.status,browser:report.browserValidation.status,currentNarrativeBrowser:'passed',editorial:report.editorialReview.status,sourceSha256,...metrics}));
