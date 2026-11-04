import fontkit from "@pdf-lib/fontkit";
import {PDFDocument,rgb,type PDFFont,type PDFPage} from "pdf-lib";
export type PublicDirectoryRow={ministry:string;volunteer:string;term:string};
export async function createDirectoryPDF(rows:PublicDirectoryRow[],churchName:string,fontData?:{regular:Uint8Array;bold:Uint8Array}):Promise<Uint8Array>{
 const doc=await PDFDocument.create();doc.registerFontkit(fontkit);
 const get=async(name:string)=>{const response=await fetch("/fonts/"+name);if(!response.ok)throw new Error("PDF fonts could not load. Please try again.");return new Uint8Array(await response.arrayBuffer());};
 const regular=fontData?.regular??await get("NotoSans-Regular.ttf"),heavy=fontData?.bold??await get("NotoSans-Bold.ttf");
 const font=await doc.embedFont(regular,{subset:true}),bold=await doc.embedFont(heavy,{subset:true});
 const clean=(value:string)=>value.replace(/[\u0000-\u001f]/g," ").replace(/[\u2011\u2013\u2014]/g,"-");
 doc.setTitle(churchName+" - Ministry directory");doc.setAuthor(churchName);doc.setSubject("Limited public ministry directory");
 const margin=42,widths=[210,180,138],x=[42,252,432];let page!:PDFPage,y=0;
 function wrap(value:string,size:number,f:PDFFont,width:number){const output:string[]=[];let line="";for(const word of clean(value).split(/\s+/)){if(f.widthOfTextAtSize((line?line+" ":"")+word,size)<=width){line+=(line?" ":"")+word;continue;}if(line){output.push(line);line="";}for(const char of word){if(f.widthOfTextAtSize(line+char,size)>width&&line){output.push(line);line="";}line+=char;}}if(line)output.push(line);return output.length?output:[""];}
 function fresh(){page=doc.addPage([612,792]);y=745;for(const line of wrap(churchName,15,bold,528)){page.drawText(line,{x:margin,y,size:15,font:bold,color:rgb(.1,.25,.36)});y-=21;}page.drawText("Ministry directory",{x:margin,y:y-4,size:11,font});y-=28;page.drawRectangle({x:margin,y:y-25,width:528,height:25,color:rgb(.1,.25,.36)});["Ministry","Volunteer","Term"].forEach((label,i)=>page.drawText(label,{x:x[i]+8,y:y-17,size:10,font:bold,color:rgb(1,1,1)}));y-=25;}
 fresh();
 for(const row of rows){const lines=[row.ministry,row.volunteer,row.term].map((value,i)=>wrap(value,10,font,widths[i]-16));const height=Math.max(...lines.map(v=>v.length))*14+18;if(y-height<48)fresh();lines.forEach((values,i)=>values.forEach((line,n)=>page.drawText(line,{x:x[i]+8,y:y-17-n*14,size:10,font,color:rgb(.12,.16,.2)})));y-=height;page.drawLine({start:{x:margin,y},end:{x:570,y},thickness:.5,color:rgb(.84,.88,.91)});}
 doc.getPages().forEach((p,i)=>p.drawText(`Page ${i+1} of ${doc.getPageCount()}`,{x:margin,y:26,size:8,font,color:rgb(.4,.45,.5)}));
 return doc.save();
}
