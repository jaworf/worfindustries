
import content from "./content.json";
export type Kind = "bigfive" | "motivations";
export type Answers = Record<string,number|null>;
export type Scores = {scales:Record<string,number|null>;domains:Record<string,number|null>};
export type Attempt = {id:string;kind:Kind;version:string;answers:Answers;scores:Scores|null;revision:number;submitted_at:string|null;created_at:string};
export type Skill = {name:string;experience:string;interest:string;notes:string};
export type ProfileData = {connection:string;service:string;joy:string;abilities:string;hope:string;occupation:string;interests:string;availability:string;contact:string;review_date:string;skills:Skill[]};
export const emptyProfile:ProfileData={connection:"",service:"",joy:"",abilities:"",hope:"",occupation:"",interests:"",availability:"unsure",contact:"ask",review_date:"",skills:[]};
export const questions=content.questions;
export const version=content.version;
export const names:Record<string,string>={O:"Creativity and exploration",C:"Organization and follow-through",E:"Social energy and engagement",A:"Cooperation and directness",N:"Emotional stability",P:"Faithfulness and discernment",S:"Care and belonging",T:"Teaching and understanding"};
export const motivationNames:Record<string,string>={A:"Pioneering and mission",P:names.P,E:"Sharing faith and invitation",S:names.S,T:names.T};
export const kindNames:Record<Kind,string>={bigfive:"Big Five personality",motivations:"Ministry Motivations"};
export const choices=["Very inaccurate","Moderately inaccurate","Neither inaccurate nor accurate","Moderately accurate","Very accurate"];
export const prompts:[keyof ProfileData,string,string][]=[
["connection","Tell us about your connection to this church.","About when did you start attending? What drew you here, or what has made this church meaningful to you?"],
["service","How have you served in the church or community?","Include current involvement and previous experience, here or elsewhere."],
["joy","Which kind of service has brought you the most joy, and why?","This could be a formal ministry or simply something you did to help someone."],
["abilities","What abilities, experience, or spiritual gifts do you believe you could contribute?","Consider work, hobbies, training, and ways others have recognized your contribution. It is fine to be unsure."],
["hope","What would you like to explore or experience in this church?","Include ministries you are curious about, ways you would like to grow, or support that would help you participate."]
];
export const skillCatalog=["Photography","Video production","Graphic design","Writing","Social media","Audio","Livestreaming","Music","Singing","Teaching","Bible study","Mentoring","Visitation","Hospitality","Cooking","Event planning","Administration","Finance","Technology","Translation","Transportation","Construction","Repairs","Gardening","Health education","Community service"];
export function scoreEntries(kind:Kind,domains:Scores["domains"]):[string,number|null][]{return (kind==="bigfive"?["O","C","E","A","N"]:["A","P","E","S","T"]).map(k=>[k,domains[k]??null]);}
export function band(n:number){return n<2.5?"LOWER":n<=3.5?"MIDDLE":"HIGHER";}
export function score(kind:Kind,answers:Answers):Scores{
 const grouped:Record<string,number[]>={}; const expected:Record<string,number>={};
 const bank=questions[kind];
 for(const key of Object.keys(answers))if(!bank.some(q=>q.id===key))throw new Error("Unknown question.");
 for(const q of bank){
 expected[q.scale]=(expected[q.scale]??0)+1;grouped[q.scale]??=[];
 const a=answers[q.id];if(a===undefined||a===null)continue;
 if(!Number.isInteger(a)||a<1||a>5)throw new Error("Invalid answer.");
 grouped[q.scale].push(q.key==="-"?6-a:a);
 }
 const scales:Scores["scales"]={};
 for(const [s,values]of Object.entries(grouped)){const n=values.length===expected[s]?values.reduce((a,b)=>a+b,0)/values.length:null;scales[s]=n===null?null:kind==="bigfive"&&s[0]==="N"?6-n:n;}
 const domains:Scores["domains"]={};
 if(kind==="motivations")Object.assign(domains,scales);
 else for(const code of ["O","C","E","A","N"]){const v=Object.entries(scales).filter(([s])=>s[0]===code).map(([,v])=>v);domains[code]=v.length===6&&v.every(v=>v!==null)?(v as number[]).reduce((a,b)=>a+b,0)/6:null;}
 return {scales,domains};
}
export function reportSections(attempt:Attempt,church:string,details=false){
 if(!attempt.scores||!attempt.submitted_at)throw new Error("Submit the assessment first.");
 if(attempt.version!==version)throw new Error("This report needs its original content version. Contact your church administrator.");
 const d=attempt.scores.domains,s=attempt.scores.scales,kind=attempt.kind;
 const label=kind==="bigfive"?names:motivationNames;
 const values=scoreEntries(kind,d),complete=values.every(([,v])=>v!==null);
 const ordered=values.filter((v):v is [string,number]=>v[1]!==null).sort((a,b)=>b[1]-a[1]);
 const top=complete?ordered.filter(([,v])=>Math.abs(v-ordered[0][1])<1e-9).map(([k])=>k):[];
 const next=complete&&top.length===1?ordered.filter(([,v])=>v<ordered[0][1]-1e-9):[];
 const seconds=next.length?next.filter(([,v])=>Math.abs(v-next[0][1])<1e-9).map(([k])=>k):[];
 const allEqual=complete&&top.length===5;
 const primary=top.length===1?top[0]:undefined,secondary=seconds.length===1?seconds[0]:undefined;
 const pair=top.length===2?top:primary&&secondary?[primary,secondary]:[];
 const pairKey=["A","P","E","S","T"].filter(k=>pair.includes(k)).join("");
 const format=(k:string,n:number|null)=>label[k]+": "+(n===null?"Not enough answers":n.toFixed(1)+" / 5");
 const vars:Record<string,string>={church_name:church,completed_date:new Date(attempt.submitted_at).toLocaleDateString("en-US",{year:"numeric",month:"long",day:"numeric"}),
 big_five_score_summary:values.map(([k,v])=>format(k,v)).join("\n"),motivation_score_summary:values.map(([k,v])=>format(k,v)).join("\n"),
 primary_motivation:motivationNames[primary??""]??"",secondary_motivation:motivationNames[secondary??""]??"",
 tied_motivations:top.map(k=>label[k]).join(", "),tied_secondary_motivations:seconds.map(k=>label[k]).join(", "),
 missing_area_names:values.filter(([,v])=>v===null).map(([k])=>label[k]).join(", ")};
 const selected=content.reports[kind].filter(r=>{
 const id=r.id;
 if(kind==="bigfive"){
 const match=/^BF-([OCEAN][1-6]?)-(LOWER|MIDDLE|HIGHER)$/.exec(id);
 if(match){const n=match[1].length===1?d[match[1]]:s[match[1]];return (match[1].length===1||details)&&n!==null&&n!==undefined&&band(n)===match[2];}
 if(id==="BF-DETAIL-INTRO")return details;
 if(id==="BF-MISSING")return !complete;
 return true;
 }
 const area=/^MM-([APEST])-(PROFILE|PRIMARY|SECONDARY|LOWER|MIDDLE|HIGHER|SUPPORT|SCRIPTURE|STEP)$/.exec(id);
 if(area){const n=d[area[1]];if(n===null||n===undefined)return false;if(area[2]==="PRIMARY")return !allEqual&&primary===area[1];if(area[2]==="SECONDARY")return !allEqual&&secondary===area[1];if(["LOWER","MIDDLE","HIGHER"].includes(area[2]))return band(n)===area[2];return true;}
 if(id.startsWith("MM-PAIR-"))return complete&&pair.length===2&&id==="MM-PAIR-"+pairKey;
 if(id==="MM-PRIMARY")return complete&&!allEqual&&!!primary;
 if(id==="MM-SECONDARY")return complete&&!allEqual&&!!primary&&!!secondary;
 if(id==="MM-TOP-TIE")return complete&&!allEqual&&top.length>1;
 if(id==="MM-SECOND-TIE")return complete&&!allEqual&&!!primary&&seconds.length>1;
 if(id==="MM-ALL-EQUAL")return allEqual;
 if(id==="MM-INCOMPLETE")return !complete;
 if(id==="MM-ALL-HIGH")return complete&&ordered.every(([,v])=>v>3.5);
 if(id==="MM-ALL-LOW")return complete&&ordered.every(([,v])=>v<2.5);
 return true;
 });
 return selected.map(r=>({id:r.id,heading:r.heading,text:r.text.replace(/\{\{(\w+)\}\}/g,(_,key:string)=>vars[key]??"Not available")}));
}
