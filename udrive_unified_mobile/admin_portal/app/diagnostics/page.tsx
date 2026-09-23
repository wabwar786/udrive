'use client';
import {useEffect,useState} from 'react';import {AdminFrame} from '../components/admin-frame';import {ErrorBox,Loading,Stat,Badge} from '../components/ui';import {apiFetch,when} from '../lib/admin-api';
type D={apiStatus:string;databaseStatus:string;latestMigration:string;pendingMigrations:number;failedNotifications:number;staleTrackingTrips:number;openEmergencies:number;openDisputes:number;checkedAt:string};

/**
 * Where the API is writing uploaded files, and whether that survives a deploy.
 *
 * Surfaced here because the alternative was reading a container log. An
 * unmounted upload volume destroys every driver document, vehicle photograph
 * and payment screenshot on the next deploy, and the only symptom is an error
 * on one attachment card — days later, in a different screen.
 */
type Storage={uploadRoot:string;uploadRootExists:boolean;fileCount:number;searchRoots:string[];ephemeral:boolean;fault:string|null};
export default function Page(){const[d,setD]=useState<D|null>(null);const[storage,setStorage]=useState<Storage|null>(null);const[error,setError]=useState('');useEffect(()=>{apiFetch<D>('/api/v1/admin/executive/diagnostics').then(setD).catch(e=>setError(e.message));apiFetch<Storage>('/api/v1/admin/verification/files/storage-status').then(setStorage).catch(()=>{/* SuperAdmin only; a missing panel is not an error worth showing */})},[]);return <AdminFrame title="System diagnostics" subtitle="Deployment, database, delivery and operational health.">{error&&<ErrorBox message={error}/>} {!d?<Loading/>:<><section className="statGrid"><Stat label="Failed notifications" value={d.failedNotifications.toLocaleString()} tone={d.failedNotifications?'orange':'green'}/><Stat label="Stale tracking trips" value={d.staleTrackingTrips.toLocaleString()} tone={d.staleTrackingTrips?'orange':'green'}/><Stat label="Open emergencies" value={d.openEmergencies.toLocaleString()} tone={d.openEmergencies?'orange':'green'}/><Stat label="Open disputes" value={d.openDisputes.toLocaleString()} tone={d.openDisputes?'orange':'green'}/></section><section className="panel"><div className="detailGrid"><div><span>API</span><Badge value={d.apiStatus}/></div><div><span>Database</span><Badge value={d.databaseStatus}/></div><div><span>Latest migration</span><strong>{d.latestMigration}</strong></div><div><span>Pending migrations</span><strong>{d.pendingMigrations}</strong></div><div><span>Checked</span><strong>{when(d.checkedAt)}</strong></div></div></section>
{storage&&<section className="panel"><header className="panelHeader"><div><h2>File storage</h2><p>Where driver documents, vehicle photographs and payment screenshots are written.</p></div></header>
{storage.fault&&<ErrorBox message={`The API cannot write to ${storage.uploadRoot}: ${storage.fault}. Uploads will fail until this is fixed — check the volume's mount path and permissions.`}/>}
{storage.ephemeral&&<ErrorBox message={`Uploads are being written to ${storage.uploadRoot}, which is inside the container image. Every deploy destroys them. Add a volume to the udrive-api service with mount path /data and set UPLOAD_ROOT=/data/uploads. Note that a volume on the database service does not help — they are separate containers.`}/>}
<div className="detailGrid"><div><span>Upload root</span><strong>{storage.uploadRoot}</strong></div><div><span>Survives a deploy</span><Badge value={storage.ephemeral?'No':'Yes'}/></div><div><span>Folder exists</span><Badge value={storage.uploadRootExists?'Yes':'No'}/></div><div><span>Writable</span><Badge value={storage.fault?'No':'Yes'}/></div><div><span>Files stored</span><strong>{storage.fileCount<0?'unreadable':storage.fileCount.toLocaleString()}</strong></div></div></section>}
</>}</AdminFrame>}
