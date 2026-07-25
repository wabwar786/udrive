import type { ReactNode } from 'react';
export function Badge({value}:{value:unknown}){const text=String(value??'—');const key=text.toLowerCase().replace(/\s+/g,'-');return <span className={`badge badge-${key}`}>{text}</span>}
export function Empty({title='Nothing here yet',copy='New records will appear here automatically.'}:{title?:string;copy?:string}){return <div className="empty"><div className="emptyIcon">◇</div><h3>{title}</h3><p>{copy}</p></div>}
export function Loading(){return <div className="loading"><span/><span/><span/> Loading live data…</div>}
export function ErrorBox({message}:{message:string}){return <div className="errorBox"><strong>Could not complete the request.</strong><span>{message}</span></div>}
export function Stat({label,value,sub,tone='emerald'}:{label:string;value:ReactNode;sub?:string;tone?:string}){return <article className={`stat stat-${tone}`}><span>{label}</span><strong>{value}</strong>{sub&&<small>{sub}</small>}</article>}
export function Modal({title,children,onClose}:{title:string;children:ReactNode;onClose:()=>void}){return <div className="modalBackdrop" onMouseDown={onClose}><section className="modal" onMouseDown={e=>e.stopPropagation()}><header><h2>{title}</h2><button className="iconButton" onClick={onClose}>×</button></header>{children}</section></div>}
export function Field({label,children}:{label:string;children:ReactNode}){return <label className="field"><span>{label}</span>{children}</label>}
