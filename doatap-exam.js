(function(root,factory){
  const api=factory();
  if(typeof module === "object" && module.exports) module.exports=api;
  root.MEDQUIZ_DOATAP=api;
})(typeof globalThis !== "undefined" ? globalThis : this,function(){
  "use strict";
  const UNKNOWN="Я не знаю ответ";
  const PREFIX="library-doatap-";
  const GROUPS=Object.freeze([
    {id:"kiniti-akiniti-prosthetiki",name:"Протезирование",greek:"Προσθετική",subjects:["akiniti-prosthetiki","kiniti-prosthetiki"]},
    {id:"stomatologia-exaktiki-aktinodiagnostiki",name:"Патология и хирургия полости рта",greek:"Παθολογία και χειρουργική στόματος",subjects:["aktinodiagnostiki","exaktiki","stomatologia"]},
    {id:"periodontologia-endodontologia-odontiki-xeirourgiki",name:"Патология и лечение зубных и пародонтальных тканей",greek:"Παθολογία και θεραπευτική οδοντικών και περιοδοντικών ιστών",subjects:["odontiki-xeirourgiki","endodontologia","periodontologia"]}
  ].map(group=>Object.freeze({...group,subjects:Object.freeze(group.subjects)})));
  function isExamId(id){ return String(id || "").startsWith(PREFIX); }
  function groupId(id){ return isExamId(id) ? id.slice(PREFIX.length) : null; }
  function selectQuestions(group,pools,random=Math.random){
    const selected=[];
    function shuffle(items){
      for(let i=items.length-1;i>0;i--){const j=Math.floor(random()*(i+1));[items[i],items[j]]=[items[j],items[i]];}
      return items;
    }
    for(const subjectId of group.subjects){
      const pool=pools[subjectId];
      if(!Array.isArray(pool) || pool.length<50) throw new Error("Для экзамена нужно не менее 50 вопросов по каждому предмету.");
      for(const q of shuffle([...pool]).slice(0,50)){
        if(!Number.isInteger(q.correct) || q.correct<0 || q.correct>=q.opts.length) throw new Error("У вопроса отсутствует корректный ключ ответа.");
        selected.push({...q,originalNum:q.originalNum || q.num,subjectId,opts:[...q.opts,UNKNOWN],letters:q.opts.map((_,i)=>q.letters?.[i] || String.fromCharCode(65+i)).concat(String.fromCharCode(65+q.opts.length))});
      }
    }
    return shuffle(selected);
  }
  function tally(questions,answers){
    let correct=0,wrong=0,unknown=0,unanswered=0;
    questions.forEach((q,i)=>{
      const answer=answers[i];
      if(answer==null) unanswered++;
      else if(q.opts[answer]===UNKNOWN && answer===q.opts.length-1) unknown++;
      else if(answer===q.correct) correct++;
      else wrong++;
    });
    const total=questions.length;
    // Integer fifths avoid floating point errors at the 50% pass boundary.
    const fifths=correct*5-wrong;
    return {total,correct,wrong,unknown,unanswered,points:fifths/5,loss:(total*5-fifths)/5,percent:total ? fifths/(total*5)*100 : 0,passed:total>0 && fifths*2>=total*5};
  }
  function format(value){return Number(value.toFixed(2)).toLocaleString("ru-RU");}
  function summary(result){
    return `Баллы: ${format(result.points)} из ${result.total} · ${format(result.percent)}% · ${result.passed ? "Порог 50% достигнут" : "Порог 50% не достигнут"}. Правильных: ${result.correct} · Ошибок: ${result.wrong} · Не знаю: ${result.unknown} · Без ответа: ${result.unanswered}. Потеря от максимума: ${format(result.loss)} балла.`;
  }
  return Object.freeze({UNKNOWN,PREFIX,GROUPS,isExamId,groupId,selectQuestions,tally,format,summary});
});
