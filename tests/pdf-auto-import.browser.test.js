const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');
const {PDFDocument, StandardFonts, rgb} = require('pdf-lib');

async function fixture(){
  const pdf = await PDFDocument.create();
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const page = pdf.addPage([600,800]);
  const line = (text,y,font=regular)=>page.drawText(text,{x:45,y,size:12,font});
  line('1. Which answer is bold?',750);
  line('A) First option',720);
  line('B) Second option',690,bold);
  line('C) Third option',660);
  line('2. Which answer has a green background?',600);
  line('A) A bold distractor',570,bold);
  page.drawRectangle({x:40,y:533,width:240,height:24,color:rgb(.7,.9,.7)});
  line('B) Green correct option',540);
  line('C) Plain distractor',510);
  line('3. No answer is marked',450);
  line('A) Plain first option',420);
  line('B) Plain second option',390);
  line('4. Two answers are bold',330);
  line('A) Bold first option',300,bold);
  line('B) Bold second option',270,bold);
  return Array.from(await pdf.save());
}

(async()=>{
  const browser = await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  try{
    const page = await browser.newPage();
    await page.setContent('<input name="detect" type="radio" value="auto" checked><div id="status"></div>');
    await page.addScriptTag({url:'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js'});
    const html = fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
    const helper = html.slice(html.indexOf('function normalizeText('),html.indexOf('function shuffle('));
    const letters = html.slice(html.indexOf('function normalizeStudentOptionLetter('),html.indexOf('function buildStudentDocxQuestions('));
    const pdfStart = html.indexOf('function isBold(');
    const parseStart = html.indexOf('async function parsePDF(');
    const parseEnd = html.indexOf('\n/*',parseStart);
    await page.addScriptTag({content:helper+'\n'+letters+'\n'+html.slice(pdfStart,parseEnd)+'\nasync function ensurePdfJs(){pdfjsLib.GlobalWorkerOptions.workerSrc="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";}'});
    const parse = bytes=>page.evaluate(async bytes=>parsePDF(new File([new Uint8Array(bytes)],'fixture.pdf')),bytes);
    const result = await parse(await fixture());
    assert.deepEqual(result.questions.map(q=>[q.num,q.correct]),[[1,1],[2,1]]);
    assert.deepEqual(result.diagnostics.noCorrect,[3]);
    assert.deepEqual(result.diagnostics.manyCorrect,['4 (A, B)']);
    assert.deepEqual(result.diagnostics.excluded,[]);
    await page.evaluate(()=>{document.querySelector('input[name="detect"]').value = 'green';});
    const greenOnly = await parse(await fixture());
    assert.deepEqual(greenOnly.questions.map(q=>[q.num,q.correct]),[[2,1]]);
    await page.evaluate(()=>{document.querySelector('input[name="detect"]').value = 'bold';});
    const boldOnly = await parse(await fixture());
    assert.deepEqual(boldOnly.questions.map(q=>[q.num,q.correct]),[[1,1],[2,0]]);
    await page.evaluate(()=>{document.querySelector('input[name="detect"]').value = 'auto';});

    const sections = await page.evaluate(()=>applyPdfPiecesToQuestions([
      {type:'text',text:'1. Question'},
      {type:'option',letter:'A',text:'First',bold:false},
      {type:'option',letter:'B',text:'Second',bold:true},
      {type:'text',text:'Объяснение: Explanation'},
      {type:'text',text:'continued'},
      {type:'text',text:'Источник: https://example.org'},
      {type:'text',text:'2. Next question'}
    ]));
    assert.equal(sections[0].opts[1].text,'Second');
    assert.equal(sections[0].explanation,'Explanation continued');
    assert.equal(sections[0].explanationSource,'https://example.org');
    assert.equal(await page.evaluate(()=>hasCheckOrCross('✓ A) Marked')),true);
    if(process.env.CHECK_PDF_PATH){
      const real = await parse(Array.from(fs.readFileSync(process.env.CHECK_PDF_PATH)));
      assert.equal(real.questions.length,15);
      assert.deepEqual(real.questions.map(q=>q.correct),[1,0,2,0,1,2,0,1,2,0,1,2,0,1,2]);
      assert.ok(real.questions.every(q=>q.explanation && q.explanationSource));
      assert.ok(real.questions.every(q=>q.opts.every(option=>!option.includes('Объяснение:') && !option.includes('Источник:'))));
    }
    console.log('PDF auto import browser: all checks passed');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
