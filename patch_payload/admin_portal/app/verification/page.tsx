'use client';

import {
  AlertTriangle,
  BadgeCheck,
  CalendarDays,
  Car,
  CheckCircle2,
  Download,
  Eye,
  FileText,
  Languages,
  MapPin,
  Phone,
  RefreshCw,
  Search,
  ShieldCheck,
  Trash2,
  UserRound,
  X,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { AdminFrame } from '../components/admin-frame';
import { Badge, Empty, ErrorBox, Loading } from '../components/ui';
import {
  apiFetch,
  apiProtectedFile,
  when,
  readSession,
} from '../lib/admin-api';
import styles from './verification.module.css';

type DriverListItem = {
  driverProfileId: string;
  userId: string;
  fullName: string;
  phoneNumber: string;
  verificationStatus: string;
  cnicMasked?: string | null;
  drivingLicenceMasked?: string | null;
  submittedAt?: string | null;
  documentCount: number;
  vehicleCount: number;
};

type DriverProfile = {
  driverProfileId: string;
  verificationStatus: string;
  cnicMasked?: string | null;
  drivingLicenceMasked?: string | null;
  dateOfBirth?: string | null;
  address?: string | null;
  emergencyContactName?: string | null;
  emergencyContactPhone?: string | null;
  bankAccountTitle?: string | null;
  payoutMethod?: string | null;
  payoutAccountMasked?: string | null;
  languages: string[];
  serviceAreas: string[];
  submittedAt?: string | null;
  reviewedAt?: string | null;
  reviewNotes?: string | null;
};

type VerificationDocument = {
  id: string;
  documentType: string;
  fileUrl: string;
  expiryDate?: string | null;
  status: string;
  reviewNotes?: string | null;
};

type VehicleListItem = {
  vehicleId: string;
  driverProfileId: string;
  driverName: string;
  registrationNumber: string;
  vehicle: string;
  status: string;
  mountainReadinessScore: number;
  documentCount: number;
};

type VehicleDetail = {
  vehicle: VehicleListItem;
  documents: VerificationDocument[];
};

type DriverDetail = {
  driver: DriverListItem;
  profile: DriverProfile;
  documents: VerificationDocument[];
  vehicles: VehicleListItem[];
};

type Selection =
  | { type: 'driver'; id: string }
  | { type: 'vehicle'; id: string };

const driverDocumentOrder = [
  'SELFIE',
  'CNIC_FRONT',
  'CNIC_BACK',
  'DRIVING_LICENCE',
];

const vehicleDocumentOrder = [
  'VEHICLE_FRONT',
  'VEHICLE_REAR',
  'VEHICLE_INTERIOR',
  'REGISTRATION_BOOK',
  'INSURANCE',
  'FITNESS_CERTIFICATE',
];

function pretty(value: string) {
  return value
    .toLowerCase()
    .split('_')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function sortDocuments(
  documents: VerificationDocument[],
  order: string[],
) {
  return [...documents].sort((a, b) => {
    const left = order.indexOf(a.documentType);
    const right = order.indexOf(b.documentType);

    return (
      (left === -1 ? 999 : left) -
      (right === -1 ? 999 : right)
    );
  });
}

export default function VerificationPage() {
  const [drivers, setDrivers] = useState<DriverListItem[]>([]);
  const [vehicles, setVehicles] = useState<VehicleListItem[]>([]);
  const [tab, setTab] = useState<'drivers' | 'vehicles'>('drivers');
  const [selection, setSelection] = useState<Selection | null>(null);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('');
  const [pageNumber, setPageNumber] = useState(1);
  const [pageSize, setPageSize] = useState(25);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const canDelete = readSession()?.user.roles.includes('SuperAdmin') ?? false;

  const load = useCallback(async () => {
    setBusy(true);
    setError('');

    try {
      const [driverRows, vehicleRows] = await Promise.all([
        apiFetch<DriverListItem[]>(
          `/api/v1/admin/verification/drivers${
            status && tab === 'drivers'
              ? `?status=${encodeURIComponent(status)}`
              : ''
          }`,
        ),
        apiFetch<VehicleListItem[]>(
          `/api/v1/admin/verification/vehicles${
            status && tab === 'vehicles'
              ? `?status=${encodeURIComponent(status)}`
              : ''
          }`,
        ),
      ]);

      setDrivers(driverRows);
      setVehicles(vehicleRows);
    } catch (loadError) {
      setError(
        loadError instanceof Error
          ? loadError.message
          : 'Verification data could not be loaded.',
      );
    } finally {
      setBusy(false);
    }
  }, [status, tab]);

  useEffect(() => {
    void load();
  }, [load]);

  const filteredDrivers = useMemo(() => {
    const value = search.trim().toLowerCase();
    if (!value) return drivers;

    return drivers.filter((driver) =>
      [
        driver.fullName,
        driver.phoneNumber,
        driver.cnicMasked,
        driver.drivingLicenceMasked,
        driver.verificationStatus,
      ]
        .filter(Boolean)
        .some((field) =>
          String(field).toLowerCase().includes(value),
        ),
    );
  }, [drivers, search]);

  const filteredVehicles = useMemo(() => {
    const value = search.trim().toLowerCase();
    if (!value) return vehicles;

    return vehicles.filter((vehicle) =>
      [
        vehicle.driverName,
        vehicle.registrationNumber,
        vehicle.vehicle,
        vehicle.status,
      ].some((field) =>
        String(field).toLowerCase().includes(value),
      ),
    );
  }, [vehicles, search]);

  useEffect(() => {
    setPageNumber(1);
  }, [tab, search, status, pageSize]);

  const currentRows =
    tab === 'drivers' ? filteredDrivers : filteredVehicles;
  const totalPages = Math.max(
    1,
    Math.ceil(currentRows.length / pageSize),
  );
  const safePage = Math.min(pageNumber, totalPages);
  const pageStart = (safePage - 1) * pageSize;
  const pagedDrivers = filteredDrivers.slice(
    pageStart,
    pageStart + pageSize,
  );
  const pagedVehicles = filteredVehicles.slice(
    pageStart,
    pageStart + pageSize,
  );

  return (
    <AdminFrame
      title="Driver & vehicle verification"
      subtitle="Open a Driver to review their complete profile, identity evidence and every vehicle document."
      actions={
        <button className="secondaryButton" onClick={() => void load()}>
          <RefreshCw size={17} />
          Refresh
        </button>
      }
    >
      {error && <ErrorBox message={error} />}

      <section className={`panel ${styles.queuePanel}`}>
        <header className={`panelHeader ${styles.queueHeader}`}>
          <div>
            <h2>Verification workspace</h2>
            <p>
              Review documents in one place before approving access
              to Kashmir tourism services.
            </p>
          </div>

          <div className={styles.toolbar}>
            <div className={styles.tabs}>
              <button
                className={tab === 'drivers' ? styles.activeTab : ''}
                onClick={() => {
                  setTab('drivers');
                  setStatus('');
                  setPageNumber(1);
                }}
              >
                <UserRound size={17} />
                Drivers
                <span>{drivers.length}</span>
              </button>
              <button
                className={tab === 'vehicles' ? styles.activeTab : ''}
                onClick={() => {
                  setTab('vehicles');
                  setStatus('');
                  setPageNumber(1);
                }}
              >
                <Car size={17} />
                Vehicles
                <span>{vehicles.length}</span>
              </button>
            </div>

            <label className={styles.search}>
              <Search size={17} />
              <input
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder={
                  tab === 'drivers'
                    ? 'Search Driver, phone or CNIC'
                    : 'Search vehicle or registration'
                }
              />
            </label>

            <select
              className={styles.statusFilter}
              value={status}
              onChange={(event) => setStatus(event.target.value)}
            >
              <option value="">All statuses</option>
              {tab === 'drivers' ? (
                <>
                  <option value="Draft">Draft</option>
                  <option value="Submitted">Submitted</option>
                  <option value="UnderReview">Under review</option>
                  <option value="ChangesRequired">
                    Changes required
                  </option>
                  <option value="Approved">Approved</option>
                  <option value="Rejected">Rejected</option>
                  <option value="Suspended">Suspended</option>
                </>
              ) : (
                <>
                  <option value="Draft">Draft</option>
                  <option value="Submitted">Submitted</option>
                  <option value="PendingReview">Pending review</option>
                  <option value="ChangesRequired">
                    Changes required
                  </option>
                  <option value="Verified">Verified</option>
                  <option value="Suspended">Suspended</option>
                  <option value="Expired">Expired</option>
                </>
              )}
            </select>

            <label className={styles.pageSizeControl}>
              <span>Rows</span>
              <select
                value={pageSize}
                onChange={(event) =>
                  setPageSize(Number(event.target.value))
                }
              >
                <option value={25}>25</option>
                <option value={50}>50</option>
                <option value={100}>100</option>
              </select>
            </label>
          </div>
        </header>

        {busy ? (
          <Loading />
        ) : tab === 'drivers' ? (
          filteredDrivers.length === 0 ? (
            <Empty
              title="No Driver applications found"
              copy="Submitted Driver applications will appear here."
            />
          ) : (
            <>
              <div className={styles.tableScroll}>
                <table className={styles.verificationTable}>
                  <thead>
                    <tr>
                      <th>#</th>
                      <th>Driver</th>
                      <th>Contact / CNIC</th>
                      <th>Documents</th>
                      <th>Vehicles</th>
                      <th>Submitted</th>
                      <th>Status</th>
                      <th aria-label="Review action" />
                    </tr>
                  </thead>
                  <tbody>
                    {pagedDrivers.map((driver, index) => (
                      <tr
                        key={driver.driverProfileId}
                        className={styles.clickableRow}
                        tabIndex={0}
                        onClick={() =>
                          setSelection({
                            type: 'driver',
                            id: driver.driverProfileId,
                          })
                        }
                        onKeyDown={(event) => {
                          if (
                            event.key === 'Enter' ||
                            event.key === ' '
                          ) {
                            event.preventDefault();
                            setSelection({
                              type: 'driver',
                              id: driver.driverProfileId,
                            });
                          }
                        }}
                      >
                        <td className={styles.serialCell}>
                          {pageStart + index + 1}
                        </td>
                        <td>
                          <div className={styles.personCell}>
                            <span className={styles.tableAvatar}>
                              {driver.fullName
                                .split(' ')
                                .map((part) => part[0])
                                .slice(0, 2)
                                .join('')
                                .toUpperCase()}
                            </span>
                            <div>
                              <strong>{driver.fullName}</strong>
                              <small>Open complete application</small>
                            </div>
                          </div>
                        </td>
                        <td>
                          <strong>{driver.phoneNumber}</strong>
                          <small>{driver.cnicMasked ?? 'CNIC not added'}</small>
                        </td>
                        <td>
                          <span className={styles.countValue}>
                            {driver.documentCount}/4
                          </span>
                        </td>
                        <td>
                          <span className={styles.countValue}>
                            {driver.vehicleCount}
                          </span>
                        </td>
                        <td>
                          {driver.submittedAt
                            ? when(driver.submittedAt)
                            : 'Not submitted'}
                        </td>
                        <td>
                          <Badge value={driver.verificationStatus} />
                        </td>
                        <td className={styles.actionCell}>
                          <button
                            type="button"
                            className={styles.reviewButton}
                            onClick={(event) => {
                              event.stopPropagation();
                              setSelection({
                                type: 'driver',
                                id: driver.driverProfileId,
                              });
                            }}
                          >
                            Review
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <TablePagination
                page={safePage}
                totalPages={totalPages}
                totalRows={filteredDrivers.length}
                pageSize={pageSize}
                onPageChange={setPageNumber}
              />
            </>
          )
        ) : filteredVehicles.length === 0 ? (
          <Empty
            title="No vehicle applications found"
            copy="Submitted vehicle records will appear here."
          />
        ) : (
          <>
            <div className={styles.tableScroll}>
              <table className={styles.verificationTable}>
                <thead>
                  <tr>
                    <th>#</th>
                    <th>Registration</th>
                    <th>Vehicle</th>
                    <th>Driver</th>
                    <th>Documents</th>
                    <th>Mountain score</th>
                    <th>Status</th>
                    <th aria-label="Review action" />
                  </tr>
                </thead>
                <tbody>
                  {pagedVehicles.map((vehicle, index) => (
                    <tr
                      key={vehicle.vehicleId}
                      className={styles.clickableRow}
                      tabIndex={0}
                      onClick={() =>
                        setSelection({
                          type: 'vehicle',
                          id: vehicle.vehicleId,
                        })
                      }
                      onKeyDown={(event) => {
                        if (
                          event.key === 'Enter' ||
                          event.key === ' '
                        ) {
                          event.preventDefault();
                          setSelection({
                            type: 'vehicle',
                            id: vehicle.vehicleId,
                          });
                        }
                      }}
                    >
                      <td className={styles.serialCell}>
                        {pageStart + index + 1}
                      </td>
                      <td>
                        <div className={styles.personCell}>
                          <span
                            className={`${styles.tableAvatar} ${styles.vehicleTableAvatar}`}
                          >
                            <Car size={17} />
                          </span>
                          <div>
                            <strong>{vehicle.registrationNumber}</strong>
                            <small>Open vehicle evidence</small>
                          </div>
                        </div>
                      </td>
                      <td>{vehicle.vehicle}</td>
                      <td>{vehicle.driverName}</td>
                      <td>
                        <span className={styles.countValue}>
                          {vehicle.documentCount}
                        </span>
                      </td>
                      <td>{vehicle.mountainReadinessScore}%</td>
                      <td>
                        <Badge value={vehicle.status} />
                      </td>
                      <td className={styles.actionCell}>
                        <button
                          type="button"
                          className={styles.reviewButton}
                          onClick={(event) => {
                            event.stopPropagation();
                            setSelection({
                              type: 'vehicle',
                              id: vehicle.vehicleId,
                            });
                          }}
                        >
                          Review
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <TablePagination
              page={safePage}
              totalPages={totalPages}
              totalRows={filteredVehicles.length}
              pageSize={pageSize}
              onPageChange={setPageNumber}
            />
          </>
        )}
      </section>

      {selection && (
        <VerificationDetail
          selection={selection}
          onClose={() => setSelection(null)}
          onChanged={load}
          canDelete={canDelete}
        />
      )}
    </AdminFrame>
  );
}

function TablePagination({
  page,
  totalPages,
  totalRows,
  pageSize,
  onPageChange,
}: {
  page: number;
  totalPages: number;
  totalRows: number;
  pageSize: number;
  onPageChange: (page: number) => void;
}) {
  const start = totalRows === 0 ? 0 : (page - 1) * pageSize + 1;
  const end = Math.min(page * pageSize, totalRows);

  return (
    <div className={styles.pagination}>
      <span>
        Showing {start}–{end} of {totalRows}
      </span>
      <div>
        <button
          type="button"
          disabled={page <= 1}
          onClick={() => onPageChange(page - 1)}
        >
          Previous
        </button>
        <strong>
          Page {page} of {totalPages}
        </strong>
        <button
          type="button"
          disabled={page >= totalPages}
          onClick={() => onPageChange(page + 1)}
        >
          Next
        </button>
      </div>
    </div>
  );
}

function VerificationDetail({
  selection,
  onClose,
  onChanged,
  canDelete,
}: {
  selection: Selection;
  onClose: () => void;
  onChanged: () => Promise<void>;
  canDelete: boolean;
}) {
  const [driverDetail, setDriverDetail] =
    useState<DriverDetail | null>(null);
  const [vehicleDetail, setVehicleDetail] =
    useState<VehicleDetail | null>(null);
  const [driverVehicles, setDriverVehicles] =
    useState<VehicleDetail[]>([]);
  const [loading, setLoading] = useState(true);
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');
  const [acting, setActing] = useState(false);

  const loadDetail = useCallback(async () => {
    setLoading(true);
    setError('');

    try {
      if (selection.type === 'driver') {
        const detail = await apiFetch<DriverDetail>(
          `/api/v1/admin/verification/drivers/${selection.id}`,
        );

        setDriverDetail(detail);
        setVehicleDetail(null);

        const fullVehicles = await Promise.all(
          detail.vehicles.map((vehicle) =>
            apiFetch<VehicleDetail>(
              `/api/v1/admin/verification/vehicles/${vehicle.vehicleId}`,
            ),
          ),
        );

        setDriverVehicles(fullVehicles);
      } else {
        const detail = await apiFetch<VehicleDetail>(
          `/api/v1/admin/verification/vehicles/${selection.id}`,
        );

        setVehicleDetail(detail);
        setDriverDetail(null);
        setDriverVehicles([]);
      }
    } catch (detailError) {
      setError(
        detailError instanceof Error
          ? detailError.message
          : 'The verification detail could not be loaded.',
      );
    } finally {
      setLoading(false);
    }
  }, [selection]);

  useEffect(() => {
    void loadDetail();
  }, [loadDetail]);

  async function decideDriver(decision: string) {
    if (
      ['ChangesRequired', 'Rejected', 'Suspended'].includes(decision) &&
      !notes.trim()
    ) {
      setError('Add review notes before this decision.');
      return;
    }

    const deleteAttachments = decision === 'Rejected' && canDelete;
    const label =
      decision === 'Approved'
        ? 'approve this Driver'
        : decision === 'ChangesRequired'
          ? 'request changes from this Driver'
          : decision === 'Suspended'
            ? 'suspend this Driver'
            : canDelete
              ? 'reject this Driver and permanently delete all Driver and vehicle attachments'
              : 'reject this Driver';

    const confirmation = deleteAttachments
      ? `Are you sure you want to ${label}? This cannot be undone.`
      : `Are you sure you want to ${label}?`;

    if (!window.confirm(confirmation)) {
      return;
    }

    setActing(true);
    setError('');

    try {
      await apiFetch(
        `/api/v1/admin/verification/drivers/${selection.id}`,
        {
          method: 'PUT',
          body: JSON.stringify({ decision, notes, deleteAttachments }),
        },
      );

      await Promise.all([loadDetail(), onChanged()]);
    } catch (decisionError) {
      setError(
        decisionError instanceof Error
          ? decisionError.message
          : 'The Driver decision could not be saved.',
      );
    } finally {
      setActing(false);
    }
  }

  async function deleteDriver() {
    if (!notes.trim()) {
      setError('Add a deletion reason in the review notes.');
      return;
    }
    if (!window.confirm('Delete this Driver from operations and permanently remove all uploaded files? Historical booking references will be retained.')) {
      return;
    }
    setActing(true);
    setError('');
    try {
      await apiFetch(`/api/v1/admin/verification/drivers/${selection.id}`, {
        method: 'DELETE',
        body: JSON.stringify({ reason: notes }),
      });
      onClose();
      await onChanged();
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'Driver could not be deleted.');
    } finally {
      setActing(false);
    }
  }

  return (
    <div className={styles.detailBackdrop} onMouseDown={onClose}>
      <aside
        className={styles.detailPanel}
        onMouseDown={(event) => event.stopPropagation()}
      >
        <header className={styles.detailHeader}>
          <div>
            <span className={styles.eyebrow}>
              {selection.type === 'driver'
                ? 'DRIVER APPLICATION'
                : 'VEHICLE APPLICATION'}
            </span>
            <h2>
              {driverDetail?.driver.fullName ??
                vehicleDetail?.vehicle.registrationNumber ??
                'Loading verification…'}
            </h2>
            <p>
              Review all submitted information and evidence before
              making a decision.
            </p>
          </div>
          <button className="iconButton" onClick={onClose} title="Close">
            <X />
          </button>
        </header>

        {loading ? (
          <Loading />
        ) : error && !driverDetail && !vehicleDetail ? (
          <ErrorBox message={error} />
        ) : driverDetail ? (
          <>
            <div className={styles.detailContent}>
              {error && <ErrorBox message={error} />}

              <DriverHero detail={driverDetail} />

              <DetailSection
                title="Personal and contact information"
                copy="Information provided by the Driver during registration."
              >
                <div className={styles.infoGrid}>
                  <Info label="Full name" value={driverDetail.driver.fullName} />
                  <Info label="Phone" value={driverDetail.driver.phoneNumber} />
                  <Info
                    label="Date of birth"
                    value={driverDetail.profile.dateOfBirth}
                  />
                  <Info
                    label="Residential address"
                    value={driverDetail.profile.address}
                    wide
                  />
                  <Info
                    label="Emergency contact"
                    value={driverDetail.profile.emergencyContactName}
                  />
                  <Info
                    label="Emergency phone"
                    value={driverDetail.profile.emergencyContactPhone}
                  />
                </div>
              </DetailSection>

              <DetailSection
                title="Identity and licence"
                copy="Masked values are shown in the portal; original evidence is displayed below."
              >
                <div className={styles.infoGrid}>
                  <Info
                    label="CNIC"
                    value={driverDetail.profile.cnicMasked}
                  />
                  <Info
                    label="Driving licence"
                    value={driverDetail.profile.drivingLicenceMasked}
                  />
                  <Info
                    label="Submitted"
                    value={
                      driverDetail.profile.submittedAt
                        ? when(driverDetail.profile.submittedAt)
                        : 'Not submitted'
                    }
                  />
                  <Info
                    label="Last reviewed"
                    value={
                      driverDetail.profile.reviewedAt
                        ? when(driverDetail.profile.reviewedAt)
                        : 'Not reviewed'
                    }
                  />
                </div>
              </DetailSection>

              <DetailSection
                title="Driver documents and photographs"
                copy="Protected files are loaded using the current Admin session and are never exposed as public URLs."
              >
                <DocumentGrid
                  documents={sortDocuments(
                    driverDetail.documents,
                    driverDocumentOrder,
                  )}
                  expected={driverDocumentOrder}
                  ownerType="driver"
                  ownerId={driverDetail.driver.driverProfileId}
                  onChanged={async () => {
                    await Promise.all([loadDetail(), onChanged()]);
                  }}
                  canDelete={canDelete}
                />
              </DetailSection>

              <DetailSection
                title="Tourism operating profile"
                copy="Languages, Kashmir service areas and payout details."
              >
                <div className={styles.infoGrid}>
                  <Info
                    label="Languages"
                    value={driverDetail.profile.languages.join(', ')}
                    icon={<Languages size={16} />}
                  />
                  <Info
                    label="Service areas"
                    value={driverDetail.profile.serviceAreas.join(', ')}
                    icon={<MapPin size={16} />}
                    wide
                  />
                  <Info
                    label="Payout method"
                    value={driverDetail.profile.payoutMethod}
                  />
                  <Info
                    label="Account title"
                    value={driverDetail.profile.bankAccountTitle}
                  />
                  <Info
                    label="Payout account"
                    value={driverDetail.profile.payoutAccountMasked}
                  />
                  <Info
                    label="Previous review notes"
                    value={driverDetail.profile.reviewNotes}
                    wide
                  />
                </div>
              </DetailSection>

              <DetailSection
                title={`Registered vehicles (${driverVehicles.length})`}
                copy="Verify each vehicle and its evidence from this same Driver review."
              >
                {driverVehicles.length === 0 ? (
                  <Empty
                    title="No vehicle registered"
                    copy="This Driver cannot be approved until at least one vehicle is verified."
                  />
                ) : (
                  <div className={styles.vehicleStack}>
                    {driverVehicles.map((vehicle) => (
                      <VehicleReviewCard
                        key={vehicle.vehicle.vehicleId}
                        detail={vehicle}
                        onChanged={async () => {
                          await Promise.all([loadDetail(), onChanged()]);
                        }}
                        onDeleted={async () => {
                          await Promise.all([loadDetail(), onChanged()]);
                        }}
                        canDelete={canDelete}
                      />
                    ))}
                  </div>
                )}
              </DetailSection>
            </div>

            <footer className={styles.decisionFooter}>
              <label>
                <span>Driver review notes</span>
                <textarea
                  rows={3}
                  value={notes}
                  onChange={(event) => setNotes(event.target.value)}
                  placeholder="Add reasons, missing information or approval notes…"
                />
              </label>

              {canDelete && (
                <div className={styles.rejectNotice}>
                  SuperAdmin rejection permanently deletes all uploaded Driver and vehicle attachments.
                </div>
              )}

              <div className={styles.decisionButtons}>
                <button
                  className="primaryButton"
                  disabled={acting}
                  onClick={() => void decideDriver('Approved')}
                >
                  <CheckCircle2 size={17} />
                  Approve Driver
                </button>
                <button
                  className="secondaryButton"
                  disabled={acting}
                  onClick={() => void decideDriver('ChangesRequired')}
                >
                  <AlertTriangle size={17} />
                  Request changes
                </button>
                <button
                  className="dangerButton"
                  disabled={acting}
                  onClick={() => void decideDriver('Rejected')}
                >
                  {canDelete && <Trash2 size={16} />}
                  {canDelete ? 'Reject & delete files' : 'Reject Driver'}
                </button>
                {canDelete && (
                  <button
                    className={styles.permanentDeleteButton}
                    disabled={acting}
                    onClick={() => void deleteDriver()}
                  >
                    <Trash2 size={16} />
                    Delete Driver
                  </button>
                )}
              </div>
            </footer>
          </>
        ) : vehicleDetail ? (
          <div className={styles.detailContent}>
            {error && <ErrorBox message={error} />}
            <VehicleReviewCard
              detail={vehicleDetail}
              onChanged={async () => {
                await Promise.all([loadDetail(), onChanged()]);
              }}
              onDeleted={async () => {
                onClose();
                await onChanged();
              }}
              canDelete={canDelete}
              expanded
            />
          </div>
        ) : null}
      </aside>
    </div>
  );
}

function DriverHero({ detail }: { detail: DriverDetail }) {
  const verifiedVehicles = detail.vehicles.filter(
    (vehicle) => vehicle.status === 'Verified',
  ).length;

  return (
    <section className={styles.driverHero}>
      <div className={styles.heroAvatar}>
        <UserRound size={32} />
      </div>
      <div className={styles.heroMain}>
        <div>
          <h3>{detail.driver.fullName}</h3>
          <p>
            <Phone size={15} />
            {detail.driver.phoneNumber}
          </p>
        </div>
        <Badge value={detail.driver.verificationStatus} />
      </div>
      <div className={styles.heroStats}>
        <div>
          <strong>{detail.documents.length}/4</strong>
          <span>Driver documents</span>
        </div>
        <div>
          <strong>{detail.vehicles.length}</strong>
          <span>Registered vehicles</span>
        </div>
        <div>
          <strong>{verifiedVehicles}</strong>
          <span>Verified vehicles</span>
        </div>
      </div>
    </section>
  );
}

function DetailSection({
  title,
  copy,
  children,
}: {
  title: string;
  copy?: string;
  children: React.ReactNode;
}) {
  return (
    <section className={styles.detailSection}>
      <header>
        <div>
          <h3>{title}</h3>
          {copy && <p>{copy}</p>}
        </div>
      </header>
      {children}
    </section>
  );
}

function Info({
  label,
  value,
  wide,
  icon,
}: {
  label: string;
  value: unknown;
  wide?: boolean;
  icon?: React.ReactNode;
}) {
  return (
    <div className={`${styles.infoItem} ${wide ? styles.wideInfo : ''}`}>
      <span>
        {icon}
        {label}
      </span>
      <strong>{value ? String(value) : '—'}</strong>
    </div>
  );
}

function DocumentGrid({
  documents,
  expected,
  ownerType,
  ownerId,
  onChanged,
  canDelete,
}: {
  documents: VerificationDocument[];
  expected: string[];
  ownerType: 'driver' | 'vehicle';
  ownerId: string;
  onChanged: () => Promise<void>;
  canDelete: boolean;
}) {
  const byType = new Map(
    documents.map((document) => [document.documentType, document]),
  );

  const allTypes = [
    ...expected,
    ...documents
      .map((document) => document.documentType)
      .filter((type) => !expected.includes(type)),
  ];

  return (
    <div className={styles.documentGrid}>
      {allTypes.map((type) => {
        const document = byType.get(type);

        return document ? (
          <ProtectedDocument
            key={document.id}
            document={document}
            previewPath={`/api/v1/admin/verification/${
              ownerType === 'driver' ? 'driver-documents' : 'vehicle-documents'
            }/${document.id}/file`}
            deletePath={`/api/v1/admin/verification/${
              ownerType === 'driver' ? 'drivers' : 'vehicles'
            }/${ownerId}/documents/${document.id}`}
            onChanged={onChanged}
            canDelete={canDelete}
          />
        ) : (
          <div className={styles.missingDocument} key={type}>
            <FileText size={25} />
            <strong>{pretty(type)}</strong>
            <span>Not uploaded</span>
          </div>
        );
      })}
    </div>
  );
}

function ProtectedDocument({
  document,
  previewPath,
  deletePath,
  onChanged,
  canDelete,
}: {
  document: VerificationDocument;
  previewPath: string;
  deletePath: string;
  onChanged: () => Promise<void>;
  canDelete: boolean;
}) {
  const [objectUrl, setObjectUrl] = useState('');
  const [contentType, setContentType] = useState('');
  const [error, setError] = useState('');
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    let active = true;
    let currentUrl = '';

    setObjectUrl('');
    setContentType('');
    setError('');

    const candidates = [document.fileUrl, previewPath].filter(
      (value, index, values) =>
        Boolean(value) && values.indexOf(value) === index,
    );

    void (async () => {
      let lastError: unknown;

      for (const candidate of candidates) {
        try {
          const file = await apiProtectedFile(candidate);

          if (!active) {
            URL.revokeObjectURL(file.objectUrl);
            return;
          }

          currentUrl = file.objectUrl;
          setObjectUrl(file.objectUrl);
          setContentType(file.contentType);
          setError('');
          return;
        } catch (candidateError) {
          lastError = candidateError;
        }
      }

      if (active) {
        setError(
          lastError instanceof Error
            ? lastError.message
            : 'Unable to load this attachment.',
        );
      }
    })();

    return () => {
      active = false;
      if (currentUrl) URL.revokeObjectURL(currentUrl);
    };
  }, [document.fileUrl, previewPath]);

  const isPdf =
    contentType.includes('pdf') ||
    document.fileUrl.toLowerCase().endsWith('.pdf');

  async function deleteAttachment() {
    if (
      !window.confirm(
        `Permanently delete ${pretty(document.documentType)}? This cannot be undone.`,
      )
    ) {
      return;
    }

    setDeleting(true);
    setError('');

    try {
      await apiFetch(deletePath, { method: 'DELETE' });
      await onChanged();
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : 'Attachment could not be deleted.',
      );
    } finally {
      setDeleting(false);
    }
  }

  return (
    <article className={styles.documentCard}>
      <div className={styles.documentPreview}>
        {!objectUrl && !error && (
          <div className={styles.fileLoading}>
            <span />
            <span />
            <span />
          </div>
        )}

        {error && (
          <div className={styles.fileError}>
            <AlertTriangle size={26} />
            <span>{error}</span>
          </div>
        )}

        {objectUrl && isPdf && (
          <iframe
            title={pretty(document.documentType)}
            src={objectUrl}
          />
        )}

        {objectUrl && !isPdf && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={objectUrl}
            alt={pretty(document.documentType)}
          />
        )}
      </div>

      <div className={styles.documentBody}>
        <div className={styles.documentTitle}>
          <div>
            <strong>{pretty(document.documentType)}</strong>
            <span>
              {document.expiryDate
                ? `Expires ${document.expiryDate}`
                : 'No expiry date'}
            </span>
          </div>
          <Badge value={document.status} />
        </div>

        {document.reviewNotes && (
          <p className={styles.documentNotes}>
            {document.reviewNotes}
          </p>
        )}

        {objectUrl && (
          <div className={styles.documentActions}>
            <a
              href={objectUrl}
              target="_blank"
              rel="noreferrer"
              className="secondaryButton"
            >
              <Eye size={16} />
              Open
            </a>
            <a
              href={objectUrl}
              download={`${document.documentType.toLowerCase()}`}
              className="secondaryButton"
            >
              <Download size={15} />
              Download
            </a>
            {canDelete && (
              <button
                type="button"
                className={styles.deleteFileButton}
                disabled={deleting}
                onClick={() => void deleteAttachment()}
              >
                <Trash2 size={15} />
                {deleting ? 'Deleting…' : 'Delete'}
              </button>
            )}
          </div>
        )}
      </div>
    </article>
  );
}

function VehicleReviewCard({
  detail,
  onChanged,
  onDeleted,
  canDelete,
  expanded = false,
}: {
  detail: VehicleDetail;
  onChanged: () => Promise<void>;
  onDeleted: () => Promise<void>;
  canDelete: boolean;
  expanded?: boolean;
}) {
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');
  const [acting, setActing] = useState(false);

  async function decide(decision: string) {
    if (
      ['ChangesRequired', 'Suspended'].includes(decision) &&
      !notes.trim()
    ) {
      setError('Add vehicle review notes before this decision.');
      return;
    }

    if (
      !window.confirm(
        `Apply "${pretty(decision)}" to vehicle ${detail.vehicle.registrationNumber}?`,
      )
    ) {
      return;
    }

    setActing(true);
    setError('');

    try {
      await apiFetch(
        `/api/v1/admin/verification/vehicles/${detail.vehicle.vehicleId}`,
        {
          method: 'PUT',
          body: JSON.stringify({ decision, notes }),
        },
      );

      setNotes('');
      await onChanged();
    } catch (decisionError) {
      setError(
        decisionError instanceof Error
          ? decisionError.message
          : 'Vehicle review could not be saved.',
      );
    } finally {
      setActing(false);
    }
  }

  async function deleteVehicle() {
    if (!notes.trim()) {
      setError('Add a deletion reason before deleting this vehicle.');
      return;
    }
    if (!window.confirm(`Delete vehicle ${detail.vehicle.registrationNumber} from operations and permanently remove its attachments?`)) {
      return;
    }
    setActing(true);
    setError('');
    try {
      await apiFetch(`/api/v1/admin/verification/vehicles/${detail.vehicle.vehicleId}`, {
        method: 'DELETE',
        body: JSON.stringify({ reason: notes }),
      });
      await onDeleted();
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'Vehicle could not be deleted.');
    } finally {
      setActing(false);
    }
  }

  return (
    <article
      className={`${styles.vehicleCard} ${
        expanded ? styles.expandedVehicle : ''
      }`}
    >
      <header className={styles.vehicleHeader}>
        <div className={styles.vehicleIcon}>
          <Car size={24} />
        </div>
        <div>
          <h4>{detail.vehicle.vehicle}</h4>
          <p>
            {detail.vehicle.registrationNumber} ·{' '}
            {detail.vehicle.driverName}
          </p>
        </div>
        <Badge value={detail.vehicle.status} />
      </header>

      <div className={styles.vehicleMetrics}>
        <div>
          <ShieldCheck size={18} />
          <strong>{detail.vehicle.mountainReadinessScore}%</strong>
          <span>Mountain readiness</span>
        </div>
        <div>
          <FileText size={18} />
          <strong>{detail.documents.length}</strong>
          <span>Documents/photos</span>
        </div>
        <div>
          <BadgeCheck size={18} />
          <strong>{detail.vehicle.status}</strong>
          <span>Verification status</span>
        </div>
      </div>

      <DocumentGrid
        documents={sortDocuments(
          detail.documents,
          vehicleDocumentOrder,
        )}
        expected={vehicleDocumentOrder.slice(0, 4)}
        ownerType="vehicle"
        ownerId={detail.vehicle.vehicleId}
        onChanged={onChanged}
        canDelete={canDelete}
      />

      {error && <ErrorBox message={error} />}

      <div className={styles.vehicleDecision}>
        <textarea
          rows={2}
          value={notes}
          onChange={(event) => setNotes(event.target.value)}
          placeholder="Vehicle review notes…"
        />
        <div>
          <button
            className="primaryButton"
            disabled={acting}
            onClick={() => void decide('Verified')}
          >
            <CheckCircle2 size={16} />
            Verify vehicle
          </button>
          <button
            className="secondaryButton"
            disabled={acting}
            onClick={() => void decide('ChangesRequired')}
          >
            Request changes
          </button>
          <button
            className="dangerButton"
            disabled={acting}
            onClick={() => void decide('Suspended')}
          >
            Suspend
          </button>
          {canDelete && (
            <button
              className={styles.permanentDeleteButton}
              disabled={acting}
              onClick={() => void deleteVehicle()}
            >
              <Trash2 size={15} />
              Delete vehicle
            </button>
          )}
        </div>
      </div>
    </article>
  );
}
