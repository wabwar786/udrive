'use client';

import {useEffect,useMemo,useState} from 'react';
import {AdminFrame} from '../components/admin-frame';
import {Badge,Empty,ErrorBox,Loading,Modal} from '../components/ui';
import {apiFetch,money,when} from '../lib/admin-api';

type PackageRow={
  id:string; title:string; startingCity:string; destination:string;
  departureAt:string; returnAt?:string|null; status:string;
  totalSeats:number; availableSeats:number; pricePerSeat:number;
  wholeVehiclePrice:number; driverName:string; vehicle:string;
  registrationNumber:string; bookingCount:number; seatsBooked:number;
  grossRevenue:number;
};

type PendingRow=PackageRow&{driverSafetyScore?:number;mountainReadinessScore?:number;reviewNotes?:string|null};

export default function Page(){
  const[rows,setRows]=useState<PackageRow[]>([]);
  const[pending,setPending]=useState<PendingRow[]>([]);
  const[selected,setSelected]=useState<PendingRow|null>(null);
  const[status,setStatus]=useState('');
  const[query,setQuery]=useState('');
  const[error,setError]=useState('');
  const[busy,setBusy]=useState(true);

  async function load(){
    setBusy(true);setError('');
    try{
      const suffix=status?`?status=${encodeURIComponent(status)}`:'';
      const[a,b]=await Promise.all([
        apiFetch<PackageRow[]>(`/api/v1/admin/tour-marketplace/packages${suffix}`),
        apiFetch<PendingRow[]>('/api/v1/admin/packages/pending'),
      ]);
      setRows(a);setPending(b);
    }catch(e){setError(e instanceof Error?e.message:'Packages could not be loaded.')}finally{setBusy(false)}
  }
  useEffect(()=>{void load()},[status]);

  const filtered=useMemo(()=>rows.filter(r=>`${r.title} ${r.startingCity} ${r.destination} ${r.driverName} ${r.registrationNumber}`.toLowerCase().includes(query.toLowerCase())),[rows,query]);
  const gross=rows.reduce((s,r)=>s+Number(r.grossRevenue||0),0);
  const seats=rows.reduce((s,r)=>s+Number(r.seatsBooked||0),0);

  return <AdminFrame title="Tourism marketplace" subtitle="Approve packages and monitor departures, inventory, bookings and revenue.">
    {error&&<ErrorBox message={error}/>} 
    <div className="metricGrid">
      <div className="metricCard"><span>Total packages</span><strong>{rows.length}</strong></div>
      <div className="metricCard"><span>Pending review</span><strong>{pending.length}</strong></div>
      <div className="metricCard"><span>Seats booked</span><strong>{seats}</strong></div>
      <div className="metricCard"><span>Gross booking value</span><strong>{money(gross)}</strong></div>
    </div>
    <div className="filterBar">
      <input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search route, Driver or registration"/>
      <select value={status} onChange={e=>setStatus(e.target.value)}>
        <option value="">All statuses</option><option>Draft</option><option>PendingApproval</option><option>Active</option><option>Paused</option><option>Rejected</option><option>Suspended</option>
      </select>
      <button className="secondaryButton" onClick={()=>void load()}>Refresh</button>
    </div>
    {pending.length>0&&<><h2>Pending approvals</h2><div className="cardGrid">{pending.map(r=><button className="packageCard" key={r.id} onClick={()=>setSelected(r)}><div><Badge value={r.status}/><h3>{r.title}</h3><p>{r.startingCity} → {r.destination}</p></div><div className="packageMeta"><span>{when(r.departureAt)}</span><strong>{money(r.pricePerSeat)} / seat</strong></div></button>)}</div></>}
    <h2>Marketplace inventory</h2>
    {busy?<Loading/>:filtered.length===0?<Empty title="No packages found"/>:<div className="tableWrap"><table><thead><tr><th>Route / package</th><th>Departure</th><th>Status</th><th>Driver & vehicle</th><th>Seats</th><th>Bookings</th><th>Revenue</th></tr></thead><tbody>{filtered.map(r=><tr key={r.id}><td><strong>{r.startingCity} → {r.destination}</strong><small>{r.title}</small></td><td>{when(r.departureAt)}</td><td><Badge value={r.status}/></td><td><strong>{r.driverName}</strong><small>{r.vehicle} · {r.registrationNumber}</small></td><td>{r.availableSeats}/{r.totalSeats} free</td><td>{r.bookingCount} · {r.seatsBooked} seats</td><td>{money(r.grossRevenue)}</td></tr>)}</tbody></table></div>}
    {selected&&<Review row={selected} close={()=>setSelected(null)} reload={load}/>} 
  </AdminFrame>
}

function Review({row,close,reload}:{row:PendingRow;close:()=>void;reload:()=>void}){
  const[notes,setNotes]=useState('');const[busy,setBusy]=useState(false);
  async function review(decision:string){setBusy(true);try{await apiFetch(`/api/v1/admin/packages/${row.id}/review`,{method:'PUT',body:JSON.stringify({decision,notes})});close();await reload()}finally{setBusy(false)}}
  return <Modal title={row.title} onClose={close}><div className="detailGrid"><div><span>Route</span><strong>{row.startingCity} → {row.destination}</strong></div><div><span>Departure</span><strong>{when(row.departureAt)}</strong></div><div><span>Inventory</span><strong>{row.availableSeats}/{row.totalSeats} seats</strong></div><div><span>Per seat</span><strong>{money(row.pricePerSeat)}</strong></div><div><span>Whole vehicle</span><strong>{money(row.wholeVehiclePrice)}</strong></div><div><span>Driver</span><strong>{row.driverName}</strong></div></div><label className="field"><span>Review notes</span><textarea rows={4} value={notes} onChange={e=>setNotes(e.target.value)}/></label><div className="buttonRow"><button disabled={busy} className="primaryButton" onClick={()=>void review('approve')}>Approve & activate</button><button disabled={busy} className="secondaryButton" onClick={()=>void review('changes')}>Request changes</button><button disabled={busy} className="dangerButton" onClick={()=>void review('reject')}>Reject</button></div></Modal>
}
