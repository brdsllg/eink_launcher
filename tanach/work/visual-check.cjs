const { chromium } = require('C:/Users/levi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const path = require('path');
const {pathToFileURL} = require('url');
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 const page=await browser.newPage({viewport:{width:800,height:1280},deviceScaleFactor:1});
 const root=path.resolve(__dirname,'..');
 for (const [book,ch,anchor] of [['ruth',3,'v-ruth-3-3'],['genesis',1,'v-genesis-1-1'],['daniel',2,'v-daniel-2-4']]){
   await page.goto(pathToFileURL(path.join(root,'work/preview',book,`chapter-${ch}.xhtml`)).href);
   await page.locator('#'+anchor).scrollIntoViewIfNeeded();
   await page.screenshot({path:path.join(root,'work',`${book}-preview.png`)});
   console.log(book,await page.evaluate(()=>({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,noterefs:document.querySelectorAll('[*|type="noteref"]').length})));
   if(book==='genesis'){
     await page.locator('#'+anchor+' a[data-category="index"]').click();
     const index=page.locator('#index-genesis-1-1');
     await index.locator('a[data-source="Rashi on Genesis"]').first().click();
     const noteId=await page.evaluate(()=>location.hash.slice(1));
     const note=page.locator('#'+noteId);
     if(!await note.locator('.note-he').count() || !await note.locator('.note-en').count()) throw new Error('Missing bilingual Rashi note');
     await page.screenshot({path:path.join(root,'work','rashi-note-preview.png')});
     await note.locator('a[href="#v-genesis-1-1"]').click();
     if(!page.url().endsWith('#v-genesis-1-1'))throw new Error('Backlink failed');
     console.log('Verse -> index -> bilingual Rashi note -> verse: PASS');
   }
 }
 await browser.close();
})();
