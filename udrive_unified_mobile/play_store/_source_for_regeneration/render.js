const { chromium } = require('playwright');
const path=require('path');
const shots=[
 ['s1_home.png','Rides across<br><em>Azad Kashmir</em>','City rides, tours and city-to-city trips in one app'],
 ['s2_car.png','See the fare<br><em>before you go</em>','Car, bike, coaster or Hiace — you choose'],
 ['s3_coaster.png','Travel together<br><em>as a group</em>','Book a whole coaster or pay per seat'],
 ['s4_destination.png','Go <em>anywhere</em><br>you need','Search any place, landmark or address'],
 ['s5_offer.png','<em>Verified</em> drivers,<br>your choice','Compare driver offers and accept the best one'],
];
(async()=>{
 const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}).catch(()=>chromium.launch());
 const src='file://'+path.join(__dirname,'src');
 let p=await b.newPage({viewport:{width:1024,height:500}});
 await p.goto(src+'/feature.html');await p.waitForTimeout(400);
 await p.screenshot({path:'out/02_feature_graphic_1024x500.png'});
 p=await b.newPage({viewport:{width:1080,height:1920}});
 for(let i=0;i<shots.length;i++){const [img,t,s]=shots[i];
  await p.goto(src+'/shot.html?i='+encodeURIComponent(img)+'&t='+encodeURIComponent(t)+'&s='+encodeURIComponent(s));
  await p.waitForTimeout(400);
  await p.screenshot({path:`out/03_phone_screenshot_${i+1}_1080x1920.png`});}
 await b.close();})();
