'use client';

import { useState, type ComponentType } from 'react';
import {
  Activity,
  BadgeCheck,
  BookOpenCheck,
  CircleDollarSign,
  FileBarChart,
  Headphones,
  PackageCheck,
  Settings,
  ShieldAlert,
  UsersRound,
} from 'lucide-react';
import { AdminFrame } from '../components/admin-frame';

type Guide = {
  icon: ComponentType<{ size?: number }>;
  titleEn: string;
  titleUr: string;
  summaryEn: string;
  summaryUr: string;
  stepsEn: string[];
  stepsUr: string[];
};

const guides: Guide[] = [
  {
    icon: Activity,
    titleEn: 'Overview and live operations',
    titleUr: 'اوورویو اور لائیو آپریشنز',
    summaryEn: 'Monitor bookings, active trips, Drivers and urgent queues.',
    summaryUr: 'بکنگ، فعال سفر، ڈرائیور اور فوری کاموں کی نگرانی کریں۔',
    stepsEn: [
      'Open Overview for the current business and operations summary.',
      'Use Operations & Dispatch for active ride handling.',
      'Use Executive Operations or Live Tracking to monitor active trips and stale GPS.',
      'Open the relevant record before taking any manual action.',
    ],
    stepsUr: [
      'موجودہ کاروباری اور آپریشنز خلاصہ دیکھنے کے لیے Overview کھولیں۔',
      'فعال رائیڈ سنبھالنے کے لیے Operations & Dispatch استعمال کریں۔',
      'فعال سفر اور جی پی ایس اسٹیٹس دیکھنے کے لیے Executive Operations یا Live Tracking کھولیں۔',
      'کوئی دستی کارروائی کرنے سے پہلے متعلقہ ریکارڈ ضرور کھولیں۔',
    ],
  },
  {
    icon: BookOpenCheck,
    titleEn: 'Bookings and ride requests',
    titleUr: 'بکنگ اور رائیڈ ریکوئسٹس',
    summaryEn: 'Search, review and manage customer ride and package bookings.',
    summaryUr: 'کسٹمر رائیڈ اور پیکیج بکنگ تلاش، جانچ اور منظم کریں۔',
    stepsEn: [
      'Search by booking reference, Customer, Driver, phone or registration.',
      'Review the booking timeline, assignment, payment and current status.',
      'Use Ride Requests for unassigned or offer-based requests.',
      'Cancel, reassign or override only when your role permits and a valid reason is recorded.',
    ],
    stepsUr: [
      'بکنگ ریفرنس، کسٹمر، ڈرائیور، فون یا رجسٹریشن سے تلاش کریں۔',
      'بکنگ ٹائم لائن، اسائنمنٹ، ادائیگی اور موجودہ اسٹیٹس دیکھیں۔',
      'غیر تفویض شدہ یا آفر والی ریکوئسٹ کے لیے Ride Requests استعمال کریں۔',
      'صرف اجازت ہونے پر اور درست وجہ درج کرکے کینسل، دوبارہ اسائن یا اوور رائیڈ کریں۔',
    ],
  },
  {
    icon: UsersRound,
    titleEn: 'Drivers, vehicles and verification',
    titleUr: 'ڈرائیور، گاڑیاں اور تصدیق',
    summaryEn: 'Verify people, documents and 2/3/4-wheel vehicles.',
    summaryUr: 'ڈرائیور، دستاویزات اور 2/3/4 وہیل گاڑیوں کی تصدیق کریں۔',
    stepsEn: [
      'Open Verification to review submitted Driver and vehicle documents.',
      'Confirm identity, expiry dates, registration, capacity and wheel type.',
      '2 Wheel includes motorcycle/scooter; 3 Wheel includes rickshaw/tuk tuk; normal cars and vans are 4 Wheel.',
      'Approve, request changes, reject or suspend with clear remarks.',
    ],
    stepsUr: [
      'جمع شدہ ڈرائیور اور گاڑی کے کاغذات دیکھنے کے لیے Verification کھولیں۔',
      'شناخت، میعاد، رجسٹریشن، گنجائش اور وہیل ٹائپ کی تصدیق کریں۔',
      '2 وہیل میں موٹر سائیکل/اسکوٹر، 3 وہیل میں رکشہ/ٹک ٹک، جبکہ عام کار اور وین 4 وہیل ہیں۔',
      'واضح ریمارکس کے ساتھ منظور، تبدیلی کی درخواست، مسترد یا معطل کریں۔',
    ],
  },
  {
    icon: PackageCheck,
    titleEn: 'Tourism marketplace and tour operations',
    titleUr: 'ٹورازم مارکیٹ پلیس اور ٹور آپریشنز',
    summaryEn: 'Approve packages and monitor departure, seats and passengers.',
    summaryUr: 'پیکیج منظور کریں اور روانگی، نشستوں اور مسافروں کی نگرانی کریں۔',
    stepsEn: [
      'Review route, itinerary, vehicle, Driver, prices and cancellation policy.',
      'Approve only complete and safe packages; otherwise request changes or reject.',
      'Monitor sold seats, passenger manifest, boarding and tour status.',
      'Use cancellation and refund controls according to policy.',
    ],
    stepsUr: [
      'روٹ، پروگرام، گاڑی، ڈرائیور، قیمت اور کینسلیشن پالیسی دیکھیں۔',
      'صرف مکمل اور محفوظ پیکیج منظور کریں؛ ورنہ تبدیلی مانگیں یا مسترد کریں۔',
      'فروخت شدہ نشستیں، مسافر فہرست، بورڈنگ اور ٹور اسٹیٹس دیکھیں۔',
      'پالیسی کے مطابق کینسلیشن اور ریفنڈ کنٹرول استعمال کریں۔',
    ],
  },
  {
    icon: CircleDollarSign,
    titleEn: 'Finance and settlements',
    titleUr: 'فنانس اور سیٹلمنٹس',
    summaryEn: 'Verify payments, payouts, refunds and reconciliation differences.',
    summaryUr: 'ادائیگی، پے آؤٹ، ریفنڈ اور ریکنسلی ایشن فرق کی تصدیق کریں۔',
    stepsEn: [
      'Check booking total, collected amount, refund, commission and Driver earning.',
      'Verify cash/bank payments only after confirming evidence.',
      'Approve or reject payout and refund requests with remarks.',
      'Use Reports & Reconciliation to investigate financial mismatches.',
    ],
    stepsUr: [
      'بکنگ ٹوٹل، وصول رقم، ریفنڈ، کمیشن اور ڈرائیور کمائی چیک کریں۔',
      'ثبوت کی تصدیق کے بعد ہی کیش یا بینک ادائیگی منظور کریں۔',
      'ریمارکس کے ساتھ پے آؤٹ اور ریفنڈ منظور یا مسترد کریں۔',
      'مالی فرق کی جانچ کے لیے Reports & Reconciliation استعمال کریں۔',
    ],
  },
  {
    icon: ShieldAlert,
    titleEn: 'Safety, SOS and disputes',
    titleUr: 'سیفٹی، ایس او ایس اور شکایات',
    summaryEn: 'Handle emergencies, safety reports and complaints promptly.',
    summaryUr: 'ایمرجنسی، حفاظتی رپورٹ اور شکایت فوری سنبھالیں۔',
    stepsEn: [
      'Open Safety Incidents immediately when an SOS or critical alert appears.',
      'Acknowledge the case, review location and contact Customer/Driver.',
      'Record every action and resolution note.',
      'Use Complaints & Disputes for non-emergency cases and financial recommendations.',
    ],
    stepsUr: [
      'ایس او ایس یا اہم الرٹ آنے پر فوراً Safety Incidents کھولیں۔',
      'کیس تسلیم کریں، لوکیشن دیکھیں اور کسٹمر/ڈرائیور سے رابطہ کریں۔',
      'ہر کارروائی اور حل کی تفصیل درج کریں۔',
      'غیر ایمرجنسی کیس اور مالی سفارش کے لیے Complaints & Disputes استعمال کریں۔',
    ],
  },
  {
    icon: FileBarChart,
    titleEn: 'Reports, audit and diagnostics',
    titleUr: 'رپورٹس، آڈٹ اور ڈائگناسٹکس',
    summaryEn: 'Review performance, accountability and system health.',
    summaryUr: 'کارکردگی، ذمہ داری اور سسٹم ہیلتھ دیکھیں۔',
    stepsEn: [
      'Use Reports for booking, revenue, commission, refund and Driver performance.',
      'Export data only when authorised.',
      'Use Audit Log to see who changed a sensitive record.',
      'Use Diagnostics for API, database, migration and delivery failures.',
    ],
    stepsUr: [
      'بکنگ، آمدنی، کمیشن، ریفنڈ اور ڈرائیور کارکردگی کے لیے Reports استعمال کریں۔',
      'صرف اجازت ہونے پر ڈیٹا ایکسپورٹ کریں۔',
      'حساس ریکارڈ کس نے تبدیل کیا دیکھنے کے لیے Audit Log کھولیں۔',
      'API، ڈیٹابیس، مائیگریشن اور ڈیلیوری خرابی کے لیے Diagnostics استعمال کریں۔',
    ],
  },
  {
    icon: Settings,
    titleEn: 'Settings and access control',
    titleUr: 'سیٹنگز اور رسائی کنٹرول',
    summaryEn: 'Change system rules carefully and follow role permissions.',
    summaryUr: 'سسٹم قواعد احتیاط سے تبدیل کریں اور رول اجازت کی پابندی کریں۔',
    stepsEn: [
      'Change commission, expiry, GPS and other settings only after approval.',
      'Do not share Admin accounts or OTP codes.',
      'Use the minimum role and permission required for each employee.',
      'Review Audit Log after important configuration changes.',
    ],
    stepsUr: [
      'کمیشن، ایکسپائری، جی پی ایس اور دوسری سیٹنگ صرف منظوری کے بعد تبدیل کریں۔',
      'ایڈمن اکاؤنٹ یا او ٹی پی کسی سے شیئر نہ کریں۔',
      'ہر ملازم کو صرف ضروری رول اور اجازت دیں۔',
      'اہم سیٹنگ تبدیل کرنے کے بعد Audit Log چیک کریں۔',
    ],
  },
  {
    icon: Headphones,
    titleEn: 'Support and escalation',
    titleUr: 'سپورٹ اور مسئلہ آگے بھیجنا',
    summaryEn: 'Use support tickets and preserve the correct reference information.',
    summaryUr: 'سپورٹ ٹکٹ استعمال کریں اور درست ریفرنس معلومات محفوظ رکھیں۔',
    stepsEn: [
      'Search the booking/user before opening a support case.',
      'Record the exact problem, time, screen and action already attempted.',
      'Never expose technical exception details to Customers or Drivers.',
      'Escalate payment, security and safety cases to the authorised team.',
    ],
    stepsUr: [
      'سپورٹ کیس بنانے سے پہلے بکنگ یا صارف تلاش کریں۔',
      'درست مسئلہ، وقت، اسکرین اور پہلے کی گئی کارروائی درج کریں۔',
      'کسٹمر یا ڈرائیور کو تکنیکی ایکسیپشن تفصیل نہ دکھائیں۔',
      'ادائیگی، سیکیورٹی اور سیفٹی کیس متعلقہ مجاز ٹیم کو بھیجیں۔',
    ],
  },
];

export default function HelpPage() {
  const [urdu, setUrdu] = useState(false);
  return (
    <AdminFrame
      title={urdu ? 'مدد اور استعمال کا طریقہ' : 'Help & user guide'}
      subtitle={urdu ? 'Udrive ایڈمن پورٹل کے تمام اہم کام آسان مراحل میں۔' : 'Simple step-by-step guidance for the Udrive Admin portal.'}
      actions={
        <div className="helpLanguageSwitch">
          <button className={!urdu ? 'active' : ''} onClick={() => setUrdu(false)}>English</button>
          <button className={urdu ? 'active' : ''} onClick={() => setUrdu(true)}>اردو</button>
        </div>
      }
    >
      <section className="helpHero" dir={urdu ? 'rtl' : 'ltr'}>
        <div>
          <span>{urdu ? 'ایڈمن گائیڈ' : 'ADMIN GUIDE'}</span>
          <h2>{urdu ? 'Udrive کو محفوظ اور درست طریقے سے چلائیں' : 'Operate Udrive safely and correctly'}</h2>
          <p>{urdu ? 'ہر سیکشن کھول کر اس کے آسان مراحل پڑھیں۔ حساس کارروائی صرف اپنے رول اور اجازت کے مطابق کریں۔' : 'Open each section and follow the simple steps. Perform sensitive actions only within your role and permissions.'}</p>
        </div>
        <BadgeCheck size={50} />
      </section>
      <section className="helpGuideGrid" dir={urdu ? 'rtl' : 'ltr'}>
        {guides.map((guide) => {
          const Icon = guide.icon;
          return (
            <details className="helpGuideCard" key={guide.titleEn}>
              <summary>
                <span className="helpGuideIcon"><Icon size={20} /></span>
                <span>
                  <strong>{urdu ? guide.titleUr : guide.titleEn}</strong>
                  <small>{urdu ? guide.summaryUr : guide.summaryEn}</small>
                </span>
              </summary>
              <ol>
                {(urdu ? guide.stepsUr : guide.stepsEn).map((step) => <li key={step}>{step}</li>)}
              </ol>
            </details>
          );
        })}
      </section>
    </AdminFrame>
  );
}
