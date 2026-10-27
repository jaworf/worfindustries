
import fontkit from "@pdf-lib/fontkit";
import {PDFDocument,rgb,type PDFPage,type PDFFont} from "pdf-lib";
import {reportSections,scoreEntries,kindNames,names,motivationNames,type Attempt} from "./core";
const palette=["#2563EB","#7C3AED","#0D9488","#EA580C","#C026D3"];
const color=(hex:string)=>rgb(parseInt(hex.slice(1,3),16)/255,parseInt(hex.slice(3,5),16)/255,parseInt(hex.slice(5,7),16)/255);
const printable=(s:string)=>s.split("").filter(c=>c==="\n"||c.charCodeAt(0)>=32).join("");
export async function createAssessmentPDF(attempt:Attempt,church:string,person:string,details=false,fontData?:{regular:Uint8Array;bold:Uint8Array}):Promise<Uint8Array>{
 const doc=await PDFDocument.create();doc.registerFontkit(fontkit);
 const get=async(name:string)=>{const r=await fetch("/fonts/"+name);if(!r.ok)throw new Error("Report fonts could not load. Please try again.");return new Uint8Array(await r.arrayBuffer());};
 const regular=fontData?.regular??await get("NotoSans-Regular.ttf"),heavy=fontData?.bold??await get("NotoSans-Bold.ttf");
 const font=await doc.embedFont(regular,{subset:true}),bold=await doc.embedFont(heavy,{subset:true});
 doc.setTitle(kindNames[attempt.kind]+" - "+church);doc.setAuthor(church);doc.setSubject("Private ministry discovery report");
 let page!:PDFPage,y=0;const margin=58,width=496;
 function fresh(){page=doc.addPage([612,792]);y=724;page.drawRectangle({x:margin,y:752,width:34,height:5,color:color("#2563EB")});}
 function room(height:number){if(y-height<68)fresh();}
 function lines(text:string,size:number,f:PDFFont):string[]{
 const result:string[]=[];for(const paragraph of printable(text).split("\n")){
 if(!paragraph){result.push("");continue;}
 let line="";for(const word of paragraph.split(/\s+/)){const next=line?line+" "+word:word;if(f.widthOfTextAtSize(next,size)>width&&line){result.push(line);line=word;}else line=next;}
 result.push(line);
 }return result;
 }
 function body(text:string){for(const l of lines(text,11,font)){room(17);if(l)page.drawText(l,{x:margin,y,size:11,font,color:rgb(.13,.17,.23)});y-=17;}y-=12;}
 function heading(text:string){const ls=lines(text,17,bold);room(ls.length*23+55);y-=12;for(const l of ls){page.drawText(l,{x:margin,y,size:17,font:bold,color:color("#1D4ED8")});y-=23;}y-=7;}
 fresh();page.drawText(printable(kindNames[attempt.kind]),{x:margin,y,size:27,font:bold,color:color("#1D4ED8")});y-=38;
 body(person+"\n"+church+"\n"+new Date(attempt.submitted_at!).toLocaleDateString("en-US",{year:"numeric",month:"long",day:"numeric"}));
 y-=12;const labels=attempt.kind==="bigfive"?names:motivationNames;
 for(const [i,[key,value]]of scoreEntries(attempt.kind,attempt.scores!.domains).entries()){
 room(54);page.drawText(printable(labels[key]??key),{x:margin,y,size:10,font:bold});page.drawText(value===null?"Not enough answers":value.toFixed(1)+" / 5",{x:margin+395,y,size:10,font});y-=18;
 page.drawRectangle({x:margin,y:y-8,width,height:10,color:rgb(.94,.95,.97)});
 if(value!==null&&value>1)page.drawRectangle({x:margin,y:y-8,width:width*((value-1)/4),height:10,color:color(palette[i%5])});
 y-=29;
 }
 body("Scores run from 1 to 5 and are not population percentiles.");
 for(const s of reportSections(attempt,church,details)){heading(s.heading);body(s.text);}
 const pages=doc.getPages();pages.forEach((p,i)=>{p.drawText(printable(church).slice(0,72),{x:margin,y:35,size:8,font,color:rgb(.4,.44,.5)});p.drawText((i+1)+" / "+pages.length,{x:506,y:35,size:8,font,color:rgb(.4,.44,.5)});});
 return doc.save();
}
export async function downloadAssessmentPDF(attempt:Attempt,church:string,person:string,details=false){
 const bytes=await createAssessmentPDF(attempt,church,person,details),blob=new Blob([bytes as BlobPart],{type:"application/pdf"}),url=URL.createObjectURL(blob);
 const a=document.createElement("a");a.href=url;a.download=attempt.kind+"-ministry-report.pdf";a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);
}
