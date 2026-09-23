// Rebuild with Node and marked installed (NODE_PATH may point to the bundled runtime).
const fs = require('fs');
const path = require('path');
const {marked} = require('marked');
const base = __dirname;
const slug = text => text.replace(/<[^>]*>/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const source = fs.readFileSync(path.join(base, 'spec.md'), 'utf8');
let rendered = marked.parse(source);
const sections = [];
rendered = rendered.replace(/<h2>(.*?)<\/h2>/g, (_, title) => {
  const id = slug(title); sections.push({id, title}); return `<h2 id="${id}">${title}</h2>`;
}).replace(/<h1>.*?<\/h1>/, '');
const reviewsDir = path.join(base, 'reviews');
const reviews = fs.existsSync(reviewsDir) ? fs.readdirSync(reviewsDir).filter(name => name.endsWith('.md')).sort() : [];
const reviewHTML = reviews.length ? reviews.map(name => `<details><summary>${name.replace('.md','').replace(/-/g,' ')}</summary>${marked.parse(fs.readFileSync(path.join(reviewsDir,name),'utf8'))}</details>`).join('') : '<p>Independent reviews are in progress. Scores will appear here after each round.</p>';
const scoreRows = reviews.map(name => { const body = fs.readFileSync(path.join(reviewsDir,name),'utf8'); const score = body.match(/## Score: ([0-9.]+) \/ 10/); return score ? `<li><span>${name.replace('.md','').replace(/-/g,' ')}</span><strong>${score[1]} / 10</strong></li>` : ''; }).join('');
const nav = sections.map(s => `<a href="#${s.id}">${s.title}</a>`).join('');
const scenarios = [
 ['reader','01','The quiet reader','One document. Room to read.'],
 ['wheel','02','The document wheel','Hold, slide, release.'],
 ['groups','03','A separate workspace','Browse groups without switching pages.'],
 ['collection','04','Your local Collection','Latest documents, contextual matches.'],
 ['history','05','A clear version history','Only versions carry a Latest badge.'],
 ['storage','06','Every byte accounted for','Shared data, protected copies, clear limits.'],
 ['missing','07','When an original disappears','Keep reading. Recover when ready.'],
 ['consent','08','A considered first use','Reading starts before archival consent.']
];
const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Shenzhen Reader — Mobile design specification</title><link rel="stylesheet" href="document.css"></head>
<body><a class="skip" href="#specification">Skip to specification</a>
<header class="masthead"><a class="wordmark" href="#top"><span class="mark">深</span> SHENZHEN <b>READER</b></a><nav aria-label="Document sections"><a href="#experience">Mockups</a><a href="#specification">Specification</a><a href="#reviews">Reviews</a></nav><span class="edition">ANDROID FIRST / IPHONE NEXT</span></header>
<main id="top"><section class="hero"><div><p class="eyebrow">A MOBILE DESIGN STUDY · SEPTEMBER 2026</p><h1>One document.<br><em>A whole workspace.</em></h1><p class="standfirst">A fast reader for PDF, EPUB and Markdown. A familiar place for your groups. A document wheel that keeps the next thought close.</p><div class="hero-actions"><a class="primary" href="#experience">Explore the mockups <span>↗</span></a><a class="text-link" href="#specification">Read the specification ↓</a></div></div><aside class="principles"><p class="eyebrow">THE DESIGN PRIORITIES</p><div><b>01</b><span>Read immediately<small>Opening never waits for an archive.</small></span></div><div><b>02</b><span>Keep less, recover more<small>Shared storage. Exact versions.</small></span></div><div><b>03</b><span>Make development observable<small>Shared UI, instant feedback, native proof.</small></span></div><p class="proposal">Proposal + interactive mockups.<br>No native app or performance claim is implied.</p></aside></section>
<section class="experience" id="experience"><div class="section-intro"><p class="eyebrow">THE EXPERIENCE</p><h2>Touch the idea.</h2><p>Choose a scene, then interact with the phone. These are simulated documents and storage figures; native rendering and timing remain implementation gates.</p></div><div class="workbench"><div class="scene-list" role="group" aria-label="Mockup scenes">${scenarios.map((s,i)=>`<button type="button" data-scene="${s[0]}" aria-pressed="${i===0}"><span>${s[1]}</span><span><strong>${s[2]}</strong><small>${s[3]}</small></span></button>`).join('')}<div class="preview-options"><label><input type="checkbox" id="large-text"> 200% text</label><a href="prototype.html" target="_blank" rel="noopener">Open full prototype ↗</a></div></div><div class="device-stage"><div class="device"><iframe id="prototype" title="Interactive Shenzhen Reader mobile mockup" src="prototype.html?scene=reader"></iframe></div><p id="scene-caption" class="caption" aria-live="polite">01 / The quiet reader · 390 × 844 design viewport</p></div></div></section>
<section class="spec-layout" id="specification"><aside class="contents"><p class="eyebrow">THE SPECIFICATION</p>${nav}<a href="#reviews">Review record</a><a href="spec.md">Markdown source ↗</a></aside><article class="spec">${rendered}</article></section>
<section id="reviews" class="review-section"><p class="eyebrow">INDEPENDENT REVIEW</p><h2>Scores with reasons.</h2><p>Text is reviewed before visuals. Scores assess this proposal and browser mockups, not an unbuilt native app. Stop at ≥9.5/10 in each phase or after eight total rounds; retain the actual findings and corrections.</p><ul class="score-trail">${scoreRows}</ul>${reviewHTML}</section>
<footer><span>Shenzhen Reader · Mobile design specification</span><a href="journal.md">Design journal ↗</a><a href="director-notes.md">Creative director's direction ↗</a><a href="#top">Back to top ↑</a></footer></main><script src="document.js"></script></body></html>`;
fs.writeFileSync(path.join(base,'index.html'), html);
console.log(`Built index.html with ${sections.length} specification sections and ${reviews.length} reviews.`);
