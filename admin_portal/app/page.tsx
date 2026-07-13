'use client';
import { useMemo, useState } from 'react';
import { Activity, BadgeCheck, Banknote, Bell, CalendarClock, Car, CheckCircle2, ChevronRight, CircleDollarSign, ClipboardCheck, Headphones, Languages, LayoutDashboard, Map, MapPinned, Menu, PackageCheck, Route, Search, Settings, ShieldAlert, Star, Users, X } from 'lucide-react';

type PackageStatus = 'Pending' | 'Approved' | 'Changes Required';
type TourPackage = { id:number; title:string; driver:string; route:string; price:number; days:number; status:PackageStatus };

const initialPackages: TourPackage[] = [
  { id:1,title:'Neelum Valley Escape',driver:'Usman Khan',route:'Muzaffarabad · Keran · Sharda',price:58000,days:3,status:'Pending' },
  { id:2,title:'Rawalakot Family Weekend',driver:'Adeel Mir',route:'Rawalakot · Banjosa · Toli Pir',price:36000,days:2,status:'Approved' },
  { id:3,title:'Leepa Valley Adventure',driver:'Naveed Ahmed',route:'Reshian · Leepa',price:76000,days:4,status:'Changes Required' },
];

const copy = {
  en:{ dashboard:'Dashboard', live:'Live Operations', bookings:'Bookings', drivers:'Drivers', packages:'Tour Packages', customers:'Customers', routes:'Routes & Advisories', payments:'Payments & Payouts', support:'Support & Safety', settings:'Settings', welcome:'Good afternoon, Shahzad', overview:'Here is what is happening across UDrive today.', pending:'Pending package approvals', approve:'Approve', changes:'Request changes', activeTrips:'Active trips', onlineDrivers:'Online drivers', todayRevenue:'Today revenue', openIncidents:'Open incidents' },
  ur:{ dashboard:'ڈیش بورڈ', live:'لائیو آپریشنز', bookings:'بکنگز', drivers:'ڈرائیورز', packages:'ٹور پیکجز', customers:'صارفین', routes:'روٹس اور اطلاعات', payments:'ادائیگیاں اور پے آؤٹ', support:'سپورٹ اور سیفٹی', settings:'ترتیبات', welcome:'دوپہر بخیر، شہزاد', overview:'آج UDrive میں ہونے والی سرگرمیوں کا خلاصہ۔', pending:'زیر التواء پیکج منظوری', approve:'منظور کریں', changes:'تبدیلی طلب کریں', activeTrips:'فعال سفر', onlineDrivers:'آن لائن ڈرائیورز', todayRevenue:'آج کی آمدنی', openIncidents:'کھلے واقعات' }
};

export default function DashboardPage(){
  const [lang,setLang]=useState<'en'|'ur'>('en');
  const [mobileOpen,setMobileOpen]=useState(false);
  const [packages,setPackages]=useState(initialPackages);
  const t=copy[lang];
  const rtl=lang==='ur';
  const pending=useMemo(()=>packages.filter(p=>p.status==='Pending'),[packages]);
  const update=(id:number,status:PackageStatus)=>setPackages(list=>list.map(p=>p.id===id?{...p,status}:p));
  return <main className={rtl?'rtl':''} dir={rtl?'rtl':'ltr'}>
    <aside className={`sidebar ${mobileOpen?'open':''}`}>
      <div className="brand"><div className="brandMark"><Route size={23}/></div><div><strong>UDrive</strong><span>Super Admin</span></div><button className="iconButton mobileClose" onClick={()=>setMobileOpen(false)}><X size={20}/></button></div>
      <nav>
        <Nav active icon={<LayoutDashboard/>} label={t.dashboard}/><Nav icon={<Map/>} label={t.live}/><Nav icon={<CalendarClock/>} label={t.bookings}/><Nav icon={<Car/>} label={t.drivers}/><Nav icon={<PackageCheck/>} label={t.packages}/><Nav icon={<Users/>} label={t.customers}/><Nav icon={<MapPinned/>} label={t.routes}/><Nav icon={<CircleDollarSign/>} label={t.payments}/><Nav icon={<Headphones/>} label={t.support}/><Nav icon={<Settings/>} label={t.settings}/>
      </nav>
      <div className="sidebarFoot"><div className="avatar">SQ</div><div><strong>Shahzad Qureshi</strong><span>Super Administrator</span></div></div>
    </aside>
    <section className="workspace">
      <header className="topbar"><button className="iconButton menuButton" onClick={()=>setMobileOpen(true)}><Menu/></button><div className="search"><Search size={19}/><input placeholder="Search bookings, drivers, packages..."/></div><button className="languageButton" onClick={()=>setLang(lang==='en'?'ur':'en')}><Languages size={18}/>{lang==='en'?'اردو':'English'}</button><button className="iconButton"><Bell size={20}/><span className="dot"/></button><div className="avatar small">SQ</div></header>
      <div className="content">
        <div className="heading"><div><h1>{t.welcome}</h1><p>{t.overview}</p></div><button className="primaryButton"><ClipboardCheck size={18}/> Export daily report</button></div>
        <div className="stats">
          <Stat icon={<Activity/>} label={t.activeTrips} value="38" delta="+12%"/><Stat icon={<Car/>} label={t.onlineDrivers} value="126" delta="+8%"/><Stat icon={<Banknote/>} label={t.todayRevenue} value="PKR 842K" delta="+18%"/><Stat warning icon={<ShieldAlert/>} label={t.openIncidents} value="3" delta="Needs review"/>
        </div>
        <div className="grid2">
          <section className="panel livePanel"><div className="panelHeader"><div><h2>{t.live}</h2><p>Muzaffarabad and Neelum service area</p></div><button className="textButton">Open full map <ChevronRight size={16}/></button></div><div className="mapVisual"><span className="road r1"/><span className="road r2"/><span className="road r3"/><Pin x="19%" y="31%" type="car"/><Pin x="45%" y="58%" type="car"/><Pin x="67%" y="30%" type="car"/><Pin x="78%" y="69%" type="alert"/><div className="mapLegend"><span><i className="green"/>Active drivers</span><span><i className="red"/>Safety alert</span></div></div></section>
          <section className="panel"><div className="panelHeader"><div><h2>Today&apos;s operations</h2><p>Booking and driver activity</p></div></div><div className="operationList"><Op icon={<CheckCircle2/>} title="124 completed bookings" text="92 rides · 32 tour packages"/><Op icon={<BadgeCheck/>} title="9 driver applications" text="4 ready for verification"/><Op icon={<Star/>} title="4.84 average rating" text="Based on 87 reviews today"/><Op icon={<Route/>} title="2 active route advisories" text="Kel–Taobat and Leepa routes"/></div></section>
        </div>
        <section className="panel packagesPanel"><div className="panelHeader"><div><h2>{t.pending}</h2><p>Review packages created by verified drivers.</p></div><span className="countPill">{pending.length} pending</span></div><div className="tableWrap"><table><thead><tr><th>Package</th><th>Driver</th><th>Route</th><th>Duration</th><th>Price</th><th>Status</th><th>Actions</th></tr></thead><tbody>{packages.map(p=><tr key={p.id}><td><strong>{p.title}</strong></td><td>{p.driver}</td><td>{p.route}</td><td>{p.days} days</td><td>PKR {p.price.toLocaleString()}</td><td><span className={`status ${p.status.toLowerCase().replaceAll(' ','-')}`}>{p.status}</span></td><td><div className="actions"><button disabled={p.status==='Approved'} onClick={()=>update(p.id,'Approved')}>{t.approve}</button><button className="outline" onClick={()=>update(p.id,'Changes Required')}>{t.changes}</button></div></td></tr>)}</tbody></table></div></section>
      </div>
    </section>
  </main>
}

function Nav({icon,label,active=false}:{icon:React.ReactNode,label:string,active?:boolean}){return <button className={`navItem ${active?'active':''}`}>{icon}<span>{label}</span></button>}
function Stat({icon,label,value,delta,warning=false}:{icon:React.ReactNode,label:string,value:string,delta:string,warning?:boolean}){return <div className="statCard"><div className={`statIcon ${warning?'warning':''}`}>{icon}</div><div><span>{label}</span><strong>{value}</strong><small>{delta}</small></div></div>}
function Op({icon,title,text}:{icon:React.ReactNode,title:string,text:string}){return <div className="op"><div className="opIcon">{icon}</div><div><strong>{title}</strong><span>{text}</span></div><ChevronRight size={18}/></div>}
function Pin({x,y,type}:{x:string,y:string,type:'car'|'alert'}){return <span className={`pin ${type}`} style={{left:x,top:y}}>{type==='car'?<Car size={16}/>:<ShieldAlert size={16}/>}</span>}
