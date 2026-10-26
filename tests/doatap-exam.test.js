const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const api=require('../doatap-exam');
const learning=require('../learning-model');
for(const group of api.GROUPS){
 const pools={};
 for(const id of group.subjects){const ctx={window:{}};vm.runInNewContext(fs.readFileSync(path.join(__dirname,id+'.js'),'utf8'),ctx);pools[id]=ctx.window.MEDQUIZ_TEST_DATA;}
 const before=JSON.stringify(pools);
 const result=api.selectQuestions(group,pools);
 assert.equal(result.length,group.subjects.length*50);
 for(const id of group.subjects){const qs=result.filter(q=>q.subjectId===id);assert.equal(qs.length,50);assert.equal(new Set(qs.map(q=>q.num)).size,50);}
 assert.equal(JSON.stringify(pools),before,'source banks must stay unchanged');
 assert.ok(result.every(q=>q.opts.at(-1)===api.UNKNOWN && q.correct<q.opts.length-1));
 assert.deepEqual(learning.makeAttemptScope({testId:api.PREFIX+group.id}),{spaceId:'dentistry',subjectId:null});
}
const q={opts:['correct','wrong',api.UNKNOWN],correct:0};
const tally=answers=>api.tally(answers.map(()=>q),answers);
assert.equal(tally([0]).points,1);
assert.equal(tally([1]).points,-0.2);
assert.equal(tally([2]).points,0);
assert.equal(tally([null]).points,0);
assert.equal(tally([1]).loss,1.2);
assert.equal(tally([2]).loss,1);
const atBoundary=tally([...Array(51).fill(0),...Array(5).fill(1),...Array(44).fill(2)]);
assert.equal(atBoundary.points,50);assert.equal(atBoundary.passed,true);
const belowBoundary=tally([...Array(51).fill(0),...Array(6).fill(1),...Array(43).fill(2)]);
assert.equal(belowBoundary.passed,false);assert.equal(belowBoundary.points,49.8);
assert.equal(tally(Array(100).fill(1)).points,-20);
assert.equal(tally([]).passed,false);
assert.throws(()=>api.selectQuestions(api.GROUPS[0],{}));
console.log('DOATAP: actual bank sampling, unchanged sources, group scopes, penalties and exact pass boundary passed');
