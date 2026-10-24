import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const story=JSON.parse(fs.readFileSync(new URL('../docs/narrative/zheng-zhilong-story.json',import.meta.url),'utf8'));
const examples={zheng_a4_s1:'zzl_a2_s1',zheng_a5_s1:'zzl_a3_s4',zheng_a5_s4:'zzl_a4_s4',yiguan_a2_s1:'zzl_a1_s2',yiguan_a4_s1:'zzl_a2_s2',yiguan_a5_s1:'zzl_a5_s2'};
for(const [oldId,newId] of Object.entries(examples)) test(`published bookmark ${oldId} keeps its historical period`,()=>assert.equal(story.legacySceneAliases[oldId],newId));
