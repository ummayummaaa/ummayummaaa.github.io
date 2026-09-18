(function(root, factory){
  const model = factory();
  if(typeof module === "object" && module.exports) module.exports = model;
  root.MEDQUIZ_LEARNING = model;
})(typeof globalThis !== "undefined" ? globalThis : this, function(){
  "use strict";

  const SPACE_STORAGE_KEY = "medquiz:last-space:v1";
  const DEFAULT_SPACE_ID = "dentistry";
  const SPACES = Object.freeze([
    Object.freeze({id:"dentistry", nameRu:"Стоматология"}),
    Object.freeze({id:"medicine", nameRu:"Лечебное дело"}),
    Object.freeze({id:"custom", nameRu:"Мои тесты"})
  ]);

  const SUBJECTS = Object.freeze([
    Object.freeze({id:"stomatologia", spaceId:"dentistry", name:"Στοματολογία", count:739}),
    Object.freeze({id:"aktinodiagnostiki", spaceId:"dentistry", name:"Ακτινοδιαγνωστική", count:665}),
    Object.freeze({id:"exaktiki", spaceId:"dentistry", name:"Εξακτική", count:769}),
    Object.freeze({id:"periodontologia", spaceId:"dentistry", name:"Περιοδοντολογία", count:450}),
    Object.freeze({id:"endodontologia", spaceId:"dentistry", name:"Ενδοδοντολογία", count:644}),
    Object.freeze({id:"odontiki-xeirourgiki", spaceId:"dentistry", name:"Οδοντική χειρουργική", count:698}),
    Object.freeze({id:"akiniti-prosthetiki", spaceId:"dentistry", name:"Ακίνιτη προσθετική", count:670}),
    Object.freeze({id:"kiniti-prosthetiki", spaceId:"dentistry", name:"Κινητή προσθετική", count:773})
  ]);

  const COMBINED_DENTISTRY_TESTS = new Set([
    "stomatologia-exaktiki-aktinodiagnostiki",
    "periodontologia-endodontologia-odontiki-xeirourgiki",
    "kiniti-akiniti-prosthetiki"
  ]);
  const SPACE_IDS = new Set(SPACES.map(item => item.id));
  const SUBJECT_BY_ID = new Map(SUBJECTS.map(item => [item.id, item]));

  function normalizedLegacyId(testId){
    return String(testId || "").replace(/^library-/, "");
  }

  function stableHash(value){
    const text = String(value || "");
    let hash = 2166136261;
    for(let index = 0; index < text.length; index++){
      hash ^= text.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16).padStart(8, "0");
  }

  function customSubjectId(userId, testId){
    if(!userId) throw new Error("A user id is required for a custom subject");
    if(!testId) throw new Error("A test id is required for a custom subject");
    return "custom-" + stableHash(String(userId) + ":" + String(testId));
  }

  function classifyLegacyTest(testId){
    const normalized = normalizedLegacyId(testId);
    const subject = SUBJECT_BY_ID.get(normalized);
    if(subject){
      return {spaceId:subject.spaceId, subjectId:subject.id, kind:"subject"};
    }
    if(COMBINED_DENTISTRY_TESTS.has(normalized)){
      return {spaceId:"dentistry", subjectId:null, kind:"combined_legacy_set"};
    }
    return {spaceId:"custom", subjectId:null, kind:"custom"};
  }

  function safeStorage(storage){
    if(storage && typeof storage.getItem === "function" && typeof storage.setItem === "function"){
      return storage;
    }
    return null;
  }

  function getSelectedSpace(storage){
    const target = safeStorage(storage);
    try{
      const stored = target && target.getItem(SPACE_STORAGE_KEY);
      return SPACE_IDS.has(stored) ? stored : DEFAULT_SPACE_ID;
    }catch(_error){
      return DEFAULT_SPACE_ID;
    }
  }

  function setSelectedSpace(spaceId, storage){
    if(!SPACE_IDS.has(spaceId)) throw new Error("Unknown MedQuiz space: " + spaceId);
    const target = safeStorage(storage);
    try{
      if(target) target.setItem(SPACE_STORAGE_KEY, spaceId);
    }catch(_error){
      // A blocked browser storage must not prevent switching during this session.
    }
    return spaceId;
  }

  function isExamKind(attemptKind){
    return attemptKind === "general_exam" || attemptKind === "block_exam" || attemptKind === "legacy_exam";
  }

  function nextErrorState(previous, result){
    const state = {
      activeError:Boolean(previous && previous.activeError),
      examCorrectStreak:Math.max(0, Math.min(3, Number(previous && previous.examCorrectStreak) || 0))
    };
    const kind = result && result.attemptKind;
    const isCorrect = Boolean(result && result.isCorrect);

    if(kind === "study") return state;
    if(kind === "training"){
      if(!isCorrect){
        if(!state.activeError) state.examCorrectStreak = 0;
        state.activeError = true;
      }
      return state;
    }
    if(!isExamKind(kind)) throw new Error("Unknown attempt kind: " + kind);

    if(!isCorrect){
      state.activeError = true;
      state.examCorrectStreak = 0;
      return state;
    }
    if(!state.activeError) return state;

    state.examCorrectStreak = Math.min(3, state.examCorrectStreak + 1);
    if(state.examCorrectStreak === 3) state.activeError = false;
    return state;
  }

  function blockStatus(blockState){
    if(!blockState || !blockState.hasChecks) return "not_started";
    if(!blockState.everPassed) return "failed";
    return Number(blockState.lastPercent) >= 90 ? "passed" : "passed_before";
  }

  function questionBlocks(questionCount, blockSize = 50){
    const count = Math.max(0, Math.floor(Number(questionCount) || 0));
    const size = Math.floor(Number(blockSize) || 0);
    if(size < 1) throw new Error("Block size must be a positive integer");
    const blocks = [];
    for(let start = 1, index = 1; start <= count; start += size, index++){
      const end = Math.min(count, start + size - 1);
      blocks.push(Object.freeze({index,start,end,count:end - start + 1}));
    }
    return blocks;
  }

  function makeAttemptScope(input){
    const legacy = classifyLegacyTest(input && input.testId);
    const spaceId = input && input.spaceId || legacy.spaceId;
    const subjectId = input && Object.prototype.hasOwnProperty.call(input, "subjectId")
      ? input.subjectId
      : legacy.subjectId;
    if(!SPACE_IDS.has(spaceId)) throw new Error("Unknown MedQuiz space: " + spaceId);
    if(spaceId !== "custom" && subjectId && SUBJECT_BY_ID.get(subjectId)?.spaceId !== spaceId){
      throw new Error("Subject does not belong to selected space");
    }
    return {spaceId, subjectId:subjectId || null};
  }

  function parseAdminViewHash(hash){
    const parts = String(hash || "").replace(/^#/, "").split("/");
    if(parts[0] !== "admin-view" || !parts[1]) return null;
    let userId;
    try{
      userId = decodeURIComponent(parts[1]);
    }catch(_error){
      return null;
    }
    if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) return null;
    return {userId, routeParts:parts.slice(2)};
  }

  function adminViewHash(userId, routeHash){
    if(!userId) throw new Error("A viewed user id is required");
    const route = String(routeHash || "#home").replace(/^#/, "") || "home";
    return `#admin-view/${encodeURIComponent(userId)}/${route}`;
  }

  function canMutateAccount(viewedUserId){
    return !viewedUserId;
  }

  return Object.freeze({
    SPACE_STORAGE_KEY,
    DEFAULT_SPACE_ID,
    SPACES,
    SUBJECTS,
    normalizedLegacyId,
    stableHash,
    customSubjectId,
    classifyLegacyTest,
    getSelectedSpace,
    setSelectedSpace,
    isExamKind,
    nextErrorState,
    blockStatus,
    questionBlocks,
    makeAttemptScope,
    parseAdminViewHash,
    adminViewHash,
    canMutateAccount
  });
});
