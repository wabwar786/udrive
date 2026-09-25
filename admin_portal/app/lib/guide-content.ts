/**
 * The admin guide, module by module, in Roman Urdu and English.
 *
 * Kept as data in its own file rather than markup inside a page, for three
 * reasons. The guide is read by people learning the portal, and it has to say
 * the same thing in the Guide button, the Help page and anywhere it is
 * surfaced later — three copies would disagree within a month. An admin who
 * needs to correct a step should be able to find one sentence and change it,
 * without touching a component. And the two languages sit in the same object,
 * line beside line, so a correction to one is impossible to make without
 * seeing the other.
 *
 * Roman Urdu is what the guide shows by default; English is a switch away.
 * The portal itself stays in English — the menu labels here are copied from
 * the sidebar word for word, so a reader can put the guide beside the portal
 * and follow along rather than translating.
 *
 * `label` on every group matches a sidebar heading exactly. When a group is
 * renamed in `admin-frame.tsx`, rename it here in the same edit — the Help
 * page is a map of the menu, and a map that names streets that no longer
 * exist is worse than no map.
 *
 * The rules are written plainly, including the unflattering ones. A guide that
 * only lists happy paths teaches people to be surprised.
 */

/** One sentence, in both languages. Neither may be left empty. */
export type Bilingual = {
  /** Roman Urdu — what the guide shows unless the reader switches. */
  ur: string;
  en: string;
};

export type GuideLanguage = 'ur' | 'en';

export type GuideSection = {
  /** The route this section documents, so it can link straight there. */
  path: string;
  /** English, matching the sidebar label exactly. */
  title: string;
  /** One line: what this screen is for. */
  purpose: Bilingual;
  /** What an admin actually does here, in order. */
  steps: Bilingual[];
  /** Things that are easy to get wrong, or that cannot be undone. */
  cautions?: Bilingual[];
  /** Who is allowed to act here. */
  roles?: Bilingual;
};

export type GuideGroup = {
  /** English, matching the sidebar heading exactly. */
  label: string;
  blurb: Bilingual;
  sections: GuideSection[];
};

/** Reads one side of a bilingual string. */
export function say(value: Bilingual, language: GuideLanguage): string {
  return language === 'en' ? value.en : value.ur;
}

/** Every word in both languages, for search. Searching only the displayed
 *  language would hide a screen from someone who typed its English name. */
export function haystack(section: GuideSection): string {
  return [
    section.title,
    section.path,
    section.purpose.ur,
    section.purpose.en,
    ...section.steps.flatMap((step) => [step.ur, step.en]),
    ...(section.cautions ?? []).flatMap((caution) => [caution.ur, caution.en]),
  ]
    .join(' ')
    .toLowerCase();
}

/**
 * The day, in the order it should be worked.
 *
 * Separate from the groups because it is not a description of a screen — it is
 * the answer to "I have just logged in, what do I do first". Every entry points
 * at a screen in DAILY OPERATIONS, in the order the queues should be cleared:
 * anything that endangers someone, then anything that blocks a customer or a
 * driver from earning, then the paperwork.
 */
export const dailyChecklist: {
  path: string;
  title: string;
  detail: Bilingual;
}[] = [
  {
    path: '/safety',
    title: 'Safety incidents',
    detail: {
      ur: 'Sab se pehle. Koi bhi SOS ya incident khula hai to baqi sab rok kar pehle us par baat karein.',
      en: 'First, always. If an SOS or incident is open, everything else waits until you have spoken to someone.',
    },
  },
  {
    path: '/',
    title: 'Overview',
    detail: {
      ur: 'Din ka naqsha. Jo number zero hona chahiye aur zero nahi hai, wohi aaj ka kaam hai.',
      en: 'The shape of the day. Any count that should be zero and is not is your queue.',
    },
  },
  {
    path: '/verification',
    title: 'Verification',
    detail: {
      ur: 'Naye driver aur gaari. Jab tak approve na ho, driver ek rupya nahi kama sakta — isay latakna mat.',
      en: 'New drivers and vehicles. Until this is cleared a driver cannot earn a rupee, so do not let it queue.',
    },
  },
  {
    path: '/wallet-topups',
    title: 'Driver top-ups',
    detail: {
      ur: 'Paisa aa gaya hai to balance credit karein. Balance khatam ho to driver online to dikhta hai magar usay requests milna band ho jati hain.',
      en: 'Credit the balance once the money has arrived. A driver whose balance runs out still shows as online but stops being sent requests.',
    },
  },
  {
    path: '/ride-requests',
    title: 'Ride requests',
    detail: {
      ur: 'Zero offers wali requests dekhein. Ek hi ilaqe mein baar baar zero ka matlab rate ya driver ki kami hai.',
      en: 'Look at requests sitting at zero offers. The same area repeatedly means a rate or a supply problem.',
    },
  },
  {
    path: '/operations',
    title: 'Operations & dispatch',
    detail: {
      ur: 'Chalti hui trips. Sab se purani bina harkat wali trip sab se zyada mushkil mein hoti hai.',
      en: 'Trips in progress. The oldest untouched trip is the one most likely to be in trouble.',
    },
  },
  {
    path: '/disputes',
    title: 'Complaints & disputes',
    detail: {
      ur: 'Shikayat ka jawab usi din. Agle din tak rakhi hui shikayat do shikayatein ban jati hai.',
      en: 'Answer a complaint the day it arrives. One left overnight becomes two.',
    },
  },
  {
    path: '/support',
    title: 'Support tickets',
    detail: {
      ur: 'Baqi sab sawal. Booking ya user pehle dhoondein, phir ticket kholein.',
      en: 'Everything else. Find the booking or the user first, then open the ticket.',
    },
  },
  {
    path: '/finance',
    title: 'Finance & settlements',
    detail: {
      ur: 'Payout purane se naye ki tarteeb mein. Refund se pehle booking milaein.',
      en: 'Work payouts oldest first. Match a refund to its booking before approving it.',
    },
  },
];

export const guideGroups: GuideGroup[] = [
  // --------------------------------------------------------------- start
  {
    label: 'Start here',
    blurb: {
      ur: 'Portal kya hai, ek ride kis raste se guzarti hai, aur woh usool jo har screen par lagte hain.',
      en: 'What the portal is, how a booking moves through it, and the rules that apply everywhere.',
    },
    sections: [
      {
        path: '/',
        title: 'How a ride actually flows',
        purpose: {
          ur: 'Ek ride ka poora safar, taake pata ho kaunsa marhala kis screen ka kaam hai.',
          en: 'The path every ride takes, so you know which screen owns which stage.',
        },
        steps: [
          {
            ur: 'Customer pickup aur destination set karta hai, gaari chunta hai, aur apna fare likhta hai. Is se ride request banti hai — Ride requests mein nazar aati hai.',
            en: 'A Customer sets a pickup and destination, picks a vehicle, and names a fare. That creates a ride request — visible under Ride requests.',
          },
          {
            ur: 'Aas paas ke driver usay dekhte hain aur apna fare bhejte hain. Har jawab ek driver offer hai.',
            en: 'Drivers within range see it and answer with their own fare. Each answer is a Driver offer.',
          },
          {
            ur: 'Customer ek offer qubool karta hai. Wahan booking ban jati hai aur driver assign ho jata hai — Bookings mein nazar aati hai.',
            en: 'The Customer accepts one offer. That creates a booking and assigns the Driver — visible under Bookings.',
          },
          {
            ur: 'Driver pickup par pohanchta hai, customer se trip OTP leta hai, aur trip shuru karta hai. Progress Operations & dispatch aur Live tracking mein hoti hai.',
            en: 'The Driver drives to the pickup, takes the trip OTP from the Customer, and starts the trip. Progress is under Operations & dispatch and Live tracking.',
          },
          {
            ur: 'Trip mukammal hoti hai, paisa Finance mein settle hota hai, aur dono taraf rating de sakti hai.',
            en: 'The trip completes, money settles under Finance, and either side may leave a rating.',
          },
        ],
        cautions: [
          {
            ur: 'Ride request aur booking ek cheez nahi. Request cancel karne ka koi nuqsan nahi; booking cancel karna us driver par lagta hai jo shayad chal bhi chuka ho.',
            en: 'A ride request is not a booking. Cancelling a request costs nothing; cancelling a booking affects a Driver who has already committed and may already be driving.',
          },
          {
            ur: 'Fare customer likhta hai aur driver jawab deta hai. Admin sirf woh rate set karta hai jis se pehla number banta hai — kisi ek ride ki aakhri qeemat kabhi nahi.',
            en: 'The Customer names the fare and the Driver answers it. The admin sets the rate that seeds that first figure — never the final price of an individual ride.',
          },
        ],
      },
      {
        path: '/',
        title: 'How this menu is arranged',
        purpose: {
          ur: 'Bayein taraf ka menu saat hisson mein hai, aur tarteeb rozana ke kaam ke mutabiq hai.',
          en: 'The menu on the left is seven groups, ordered by how often you need them.',
        },
        steps: [
          {
            ur: 'DAILY OPERATIONS — rozana ka kaam. Log in karne ke baad ka pehla hissa yahi hai.',
            en: 'DAILY OPERATIONS — the work of the day. This is where you land after logging in.',
          },
          {
            ur: 'PEOPLE & FLEET — driver, customer aur gaariyan. Zaroorat par khulta hai, har roz nahi.',
            en: 'PEOPLE & FLEET — drivers, customers and vehicles. Opened when needed, not daily.',
          },
          {
            ur: 'TOURISM — package, destination, hotel, route aur road advisories.',
            en: 'TOURISM — packages, destinations, hotels, routes and road advisories.',
          },
          {
            ur: 'PRICING & MONEY — rate, zone, petrol, route insights, finance.',
            en: 'PRICING & MONEY — rates, zones, fuel, route insights, finance.',
          },
          {
            ur: 'TRUST & SAFETY — SOS, shikayat, support ticket.',
            en: 'TRUST & SAFETY — SOS, complaints, support tickets.',
          },
          {
            ur: 'REPORTS — hisaab aur record. SETUP — settings jo ek baar set hoti hain aur phir chalti rehti hain.',
            en: 'REPORTS — figures and records. SETUP — the settings you configure once and leave alone.',
          },
        ],
        cautions: [
          {
            ur: 'Har group par click kar ke usay band kiya ja sakta hai. Jo band karein ge woh agli baar bhi band milega, isi browser mein.',
            en: 'Click a group heading to fold it away. A folded group stays folded next time, in this browser.',
          },
        ],
      },
      {
        path: '/',
        title: 'Roles and what each can do',
        purpose: {
          ur: 'Portal role ke hisab se rokta hai. Apna role maloom ho to band button par waqt zaya nahi hota.',
          en: 'The portal restricts by role. Knowing yours saves guessing at a locked button.',
        },
        steps: [
          {
            ur: 'SuperAdmin — sab kuch, delete aur commission rules samet.',
            en: 'SuperAdmin — everything, including deletion and commission rules.',
          },
          {
            ur: 'Admin — har operational kaam: verification, pricing, disputes, refund.',
            en: 'Admin — everything operational: verification, pricing, disputes, refunds.',
          },
          {
            ur: 'Manager — rozana dispatch aur booking, aur verification. Support tickets Manager ke pas nahi hain.',
            en: 'Manager — day-to-day dispatch and bookings, and verification. Support tickets are not open to Manager.',
          },
          {
            ur: 'Operations — dispatch, booking, support tickets aur verification.',
            en: 'Operations — dispatch, bookings, support tickets and verification.',
          },
          {
            ur: 'FinanceOfficer — payout, refund aur pricing rates. Reconcile aur commission rules sirf SuperAdmin ke pas hain.',
            en: 'FinanceOfficer — payouts, refunds and pricing rates. Reconciliation and commission rules are SuperAdmin only.',
          },
          {
            ur: 'SupportAgent — ticket aur maloomat. Paisa nahi, verification nahi — magar booking ka status yeh bhee badal sakta hai.',
            en: 'SupportAgent — tickets and lookups. No money, no verification — but this role can change a booking’s status.',
          },
          {
            ur: 'VerificationOfficer, SafetyOfficer aur TourismManager bhee portal mein aa sakte hain, apne apne hisse ke ikhtiyar ke sath.',
            en: 'VerificationOfficer, SafetyOfficer and TourismManager can sign in too, each with rights over their own area.',
          },
        ],
        cautions: [
          {
            ur: 'Button dabane par kuch na ho to aksar matlab yeh hai ke aap ka role yeh kaam nahi kar sakta, portal kharab nahi hua. Dobara koshish karne ke bajaye upar wale role se kahein.',
            en: 'A button that does nothing usually means your role cannot do it, not that the portal is broken. Check with whoever holds the higher role rather than retrying.',
          },
        ],
      },
    ],
  },

  // ---------------------------------------------------- daily operations
  {
    label: 'DAILY OPERATIONS',
    blurb: {
      ur: 'Woh saat screens jo har roz kholni hain, usi tarteeb mein jis tarteeb se kaam karna hai.',
      en: 'The seven screens you open every day, in the order they should be worked.',
    },
    sections: [
      {
        path: '/',
        title: 'Overview',
        purpose: {
          ur: 'Ek nazar mein poora din, aur woh cheezein jo kisi ka intezar kar rahi hain.',
          en: 'The day at a glance, and what is waiting for someone.',
        },
        steps: [
          {
            ur: 'Sab se pehle upar wale numbers parhein — chalti hui trips, pending verification, khuli hui disputes.',
            en: 'Read the headline counts first — active trips, pending verifications, open disputes.',
          },
          {
            ur: 'Jo number zero hona chahiye aur zero nahi hai, wohi aaj ki qatar hai.',
            en: 'Anything with a number that should be zero is your queue for the day.',
          },
          {
            ur: 'Kuch karne se pehle poora record kholein. Sirf dashboard ke number par kabhi faisla na karein.',
            en: 'Open the record before acting. Never act from a dashboard count alone.',
          },
        ],
      },
      {
        path: '/ride-requests',
        title: 'Ride requests',
        purpose: {
          ur: 'Woh customer jo ride maang rahe hain magar abhi tak koi driver nahi mila.',
          en: 'Customers who are asking for a ride but do not have one yet.',
        },
        steps: [
          {
            ur: 'Offers ka number dekhein. Zero par khari request ka matlab hai kisi driver ne yeh fare nahi liya.',
            en: 'Watch the offers count. A request sitting at zero offers means no Driver has taken the fare.',
          },
          {
            ur: 'Ek hi ilaqe mein baar baar zero offers ka matlab aksar yeh hota hai ke wahan ka per-km rate kam hai, ya koi driver online nahi. Kharabi samajhne se pehle Pricing aur online driver count dekhein.',
            en: 'Repeated zero-offer requests in one area usually mean the per-km rate there is too low, or nobody is online. Check Pricing and the online Driver count before assuming a fault.',
          },
          {
            ur: 'Requests khud khatam ho jati hain. Inhein saaf karne ki zaroorat nahi.',
            en: 'Requests expire on their own. There is nothing to clean up.',
          },
          {
            ur: 'Agar ek hi route par mahine bhar yeh masla rahe to Route insights kholein — wahan yeh number route ke hisab se jama hota hai.',
            en: 'If one route keeps doing this for weeks, open Route insights — it collects exactly this figure per route.',
          },
        ],
      },
      {
        path: '/bookings',
        title: 'Bookings',
        purpose: {
          ur: 'Woh rides jinhein driver mil chuka hai. Trip ka asal record yahi hai.',
          en: 'Rides that have a Driver. This is the record of the trip.',
        },
        steps: [
          {
            ur: 'Booking reference, customer ka naam ya phone number se dhoondein.',
            en: 'Search by booking reference, Customer name or phone.',
          },
          {
            ur: 'Booking khol kar fare, driver, gaari aur poori status history dekhein.',
            en: 'Open a booking to see the fare, the Driver, the vehicle and the full status history.',
          },
          {
            ur: 'Status history hi sach hai — kya hua aur kab hua. Dispute mein kisi ki baat mannay se pehle yeh parhein.',
            en: 'The status history is the truth about what happened and when. Read it before believing either side of a dispute.',
          },
        ],
        cautions: [
          {
            ur: 'Yahan cancel karna ek asli driver par lagta hai jo shayad raste mein ho. Wajah zaroor likhein.',
            en: 'Cancelling here affects a real Driver who may already be driving. Record why.',
          },
        ],
      },
      {
        path: '/operations',
        title: 'Operations & dispatch',
        purpose: {
          ur: 'Chalti hui trips ka desk.',
          en: 'The desk for trips in progress.',
        },
        steps: [
          {
            ur: 'Aakhri harkat ke hisab se tarteeb lagayein. Sab se purani bina harkat wali trip sab se zyada mushkil mein hoti hai.',
            en: 'Sort by last activity. The oldest untouched trip is the one most likely to be in trouble.',
          },
          {
            ur: 'DriverEnRoute par atki hui trip jiska GPS kai minute se band hai — usay status badalne ki nahi, phone call ki zaroorat hai.',
            en: 'A trip stuck at DriverEnRoute with no GPS for several minutes needs a phone call, not a status change.',
          },
          {
            ur: 'Status haath se sirf tab badlein jab kisi se baat ho chuki ho aur asli soorat-e-haal maloom ho.',
            en: 'Change a status by hand only when you have spoken to someone and know the real state.',
          },
        ],
        cautions: [
          {
            ur: 'Zabardasti status badalna masla chhupata hai, theek nahi karta. Driver app wohi bhejti rahegi jo usay nazar aa raha hai.',
            en: 'Forcing a status hides the problem instead of fixing it. The Driver app will keep reporting what it sees.',
          },
        ],
      },
      {
        path: '/live-tracking',
        title: 'Live tracking',
        purpose: {
          ur: 'Is waqt gaariyan kahan hain.',
          en: 'Where the vehicles are right now.',
        },
        steps: [
          {
            ur: 'Purane marker ka matlab hai driver app ne bhejna band kar diya — aksar signal, kabhi app band.',
            en: 'Stale markers mean the Driver app has stopped reporting — usually signal, sometimes a closed app.',
          },
          {
            ur: '"Meri ride kahan hai" wali calls ka jawab isi se dein, driver ko chalte hue phone kiye baghair.',
            en: 'Use it to answer "where is my ride" calls without phoning the Driver mid-drive.',
          },
        ],
      },
      {
        path: '/verification',
        title: 'Verification',
        purpose: {
          ur: 'Driver aur gaari ki manzoori. Portal ki sab se bhaari zimmedari wali screen.',
          en: 'Approving Drivers and vehicles. The most consequential screen in the portal.',
        },
        steps: [
          {
            ur: 'Submission khol kar har document banday se milaein: CNIC, licence, registration.',
            en: 'Open the submission and check every document against the person: CNIC, licence, registration.',
          },
          {
            ur: 'Dekhein ke licence ki tareekh guzri hui na ho aur naam CNIC se milta ho.',
            en: 'Confirm the licence has not expired and the name matches the CNIC.',
          },
          {
            ur: 'Gaari ki registration gaari ki tasweeron se milaein.',
            en: 'Confirm the vehicle registration matches the vehicle photographs.',
          },
          {
            ur: 'Approve karein, ya aisi wajah ke sath reject karein jis par driver amal kar sake.',
            en: 'Approve, or reject with a reason the Driver can act on.',
          },
        ],
        cautions: [
          {
            ur: 'Ek approval ka matlab hai ek ajnabi customer ke sath gaari mein baitha hai. Sahi darkhwast reject karne se driver ka ek din jata hai; ghalat darkhwast approve karne se kisi ka bohot zyada.',
            en: 'An approval puts a stranger in a car with a Customer. Rejecting a good application costs a Driver a day; approving a bad one costs someone much more.',
          },
          {
            ur: 'Bina wajah ke "Rejected" faisla nahi, deewar hai. Likhein ke kya theek karna hai.',
            en: '"Rejected" with no reason is not a decision, it is a wall. Write what has to be fixed.',
          },
          {
            ur: 'Driver kisi customer ke map par tab tak nahi aata jab tak driver Approved aur gaari Verified dono na hon.',
            en: 'A Driver cannot appear on any Customer map until both the Driver is Approved and the vehicle is Verified.',
          },
          {
            ur: 'Approve karne ka ikhtiyar paanch roles ke pas hai — SuperAdmin, Admin, Manager, Operations aur VerificationOfficer. Yeh sirf do bando ka kaam nahi, is liye tay karein ke aap ki team mein yeh kaun karta hai.',
            en: 'Five roles can approve here — SuperAdmin, Admin, Manager, Operations and VerificationOfficer. This is not restricted to two people, so decide who on your team actually does it.',
          },
        ],
        roles: {
          ur: 'SuperAdmin, Admin, Manager, Operations, VerificationOfficer. Delete sirf SuperAdmin ya Admin.',
          en: 'SuperAdmin, Admin, Manager, Operations, VerificationOfficer. Deleting is SuperAdmin or Admin only.',
        },
      },
      {
        path: '/wallet-topups',
        title: 'Driver top-ups',
        purpose: {
          ur: 'Driver ke commission balance mein paisa daalne se pehle tasdeeq ke paisa waqai aaya hai.',
          en: 'Confirm money has arrived before crediting a driver’s commission balance.',
        },
        steps: [
          {
            ur: 'Driver ka bheja hua reference apne bank ya easypaisa record se milaein.',
            en: 'Match the reference the driver submitted against your own bank or Easypaisa record.',
          },
          {
            ur: 'Milne par approve karein — balance usi waqt driver ke account mein chala jata hai.',
            en: 'Approve once it matches — the balance reaches the driver immediately.',
          },
          {
            ur: 'Na milne par reject karein aur wajah likhein, taake driver sahi reference dobara bhej sake.',
            en: 'Reject with a reason when it does not, so the driver can resubmit with the right reference.',
          },
        ],
        cautions: [
          {
            ur: 'Approve karna paisa dena hai. Bina record dekhe kabhi approve na karein.',
            en: 'Approving is handing over money. Never approve without seeing the record.',
          },
          {
            ur: 'Balance kam se kam hadd se neeche jate hi driver ko nayi requests milna band ho jati hain — woh online to dikhta rehta hai, bas usay kuch bheja nahi jata. Chalti hui trip par koi asar nahi. Is liye yeh qatar rozana khali karein.',
            en: 'Once a balance falls below the minimum the driver stops being sent new requests — they still show as online, nothing is simply offered to them. A trip already under way is unaffected. So clear this queue daily.',
          },
        ],
        roles: {
          ur: 'SuperAdmin, Admin, FinanceOfficer',
          en: 'SuperAdmin, Admin, FinanceOfficer',
        },
      },
    ],
  },

  // ------------------------------------------------------ people & fleet
  {
    label: 'PEOPLE & FLEET',
    blurb: {
      ur: 'Kaun chala sakta hai, aur kis cheez mein.',
      en: 'Who is allowed to drive, and in what.',
    },
    sections: [
      {
        path: '/drivers',
        title: 'Drivers',
        purpose: {
          ur: 'Driver ki fehrist, unka maqam aur unki history.',
          en: 'The Driver roster, their standing and their history.',
        },
        steps: [
          {
            ur: 'Shikayat ya support call ke waqt driver dhoondne ke liye istemal karein.',
            en: 'Use it to look up a Driver during a complaint or a support call.',
          },
          {
            ur: 'Suspension driver ko foran offline kar deti hai aur nayi requests rok deti hai.',
            en: 'Suspension takes a Driver offline immediately and stops new requests reaching them.',
          },
        ],
        cautions: [
          {
            ur: 'Suspension warning nahi hai. Yeh us din ki kamai cheen leti hai. Safety ke ilawa har cheez ke liye disputes ka raasta istemal karein.',
            en: 'Suspension is not a warning. It removes someone’s income that day. Use the disputes process for anything short of a safety concern.',
          },
        ],
      },
      {
        path: '/customers',
        title: 'Customers',
        purpose: {
          ur: 'Customer ke accounts aur portal ke staff accounts.',
          en: 'Customer accounts and portal staff accounts.',
        },
        steps: [
          {
            ur: 'Staff account hamesha us sab se chhote role par banayein jis se uska kaam ho jaye.',
            en: 'Create staff accounts with the lowest role that lets them do their job.',
          },
          {
            ur: 'Koi banda chhor de to usi din access khatam karein, mahine ke aakhir mein nahi.',
            en: 'Remove access the day someone leaves, not at the end of the month.',
          },
        ],
      },
      {
        path: '/vehicles',
        title: 'Vehicles',
        purpose: {
          ur: 'Poora fleet, aur woh tasweerein jo customer gaari chunte waqt dekhta hai.',
          en: 'The fleet, and the photographs Customers see when choosing a vehicle.',
        },
        steps: [
          {
            ur: 'Har category ke liye ek saaf tasweer lagayein: Car, Bike, Coster, Hiace.',
            en: 'Upload one clear photograph per category: Car, Bike, Coster, Hiace.',
          },
          {
            ur: 'Charon ka andaz ek jaisa rakhein — ek hi rukh, ek hi background — warna picker alag alag apps se jurra hua lagta hai.',
            en: 'Use the same style for all four — same angle, same background — or the picker looks assembled from different apps.',
          },
          {
            ur: 'Jis category ki tasweer nahi hogi, app mein uski jagah saada icon aa jata hai.',
            en: 'A category with no photograph falls back to a plain icon in the app.',
          },
        ],
        cautions: [
          {
            ur: 'Customer gaari ka andaza isi tasweer se lagata hai. Andheri ya kati hui tasweer achi gaari ko buri dikhati hai.',
            en: 'This is what the Customer judges the vehicle by. A dark or cropped photograph makes a good vehicle look worse than it is.',
          },
        ],
      },
    ],
  },

  // ------------------------------------------------------------ tourism
  {
    label: 'TOURISM',
    blurb: {
      ur: 'Woh sab jo Explore mein nazar aata hai, aur woh log jo usay bhejte hain.',
      en: 'Everything Customers see in Explore, and the people who submit it.',
    },
    sections: [
      {
        path: '/packages',
        title: 'Tour packages',
        purpose: {
          ur: 'Driver ki taraf se pesh kiye gaye kai din ke tour.',
          en: 'Multi-day tour products offered by Drivers.',
        },
        steps: [
          {
            ur: 'Live hone se pehle package dekhein: route, seats, qeemat, aur kya kya shamil hai.',
            en: 'Review a package before it goes live: route, seats, price, what is included.',
          },
          {
            ur: 'Tour ki qeemat har driver apni gaari par khud rakhta hai, yahan se nahi.',
            en: 'Tour pricing is set by each Driver on their own vehicle, not here.',
          },
        ],
      },
      {
        path: '/destinations',
        title: 'Destinations',
        purpose: {
          ur: 'Explore mein dikhaye jane wale sayahati maqamat.',
          en: 'Tourism destinations shown in Explore.',
        },
        steps: [
          {
            ur: 'Tasweerein mausam ke mutabiq rakhein. Ghalat mausam ki tasweer ghalat umeed paida karti hai.',
            en: 'Keep photographs current. An out-of-season photograph sets the wrong expectation.',
          },
          {
            ur: 'Har maqam ka naam wohi likhein jo log bolte hain, warna search mein nahi milega.',
            en: 'Name each place the way people say it, or search will not find it.',
          },
        ],
      },
      {
        path: '/hotels',
        title: 'Hotels & approvals',
        purpose: {
          ur: 'Hotel ki listing aur woh malikan jo darkhwast bhejte hain.',
          en: 'Hotel listings and the owners who submit them.',
        },
        steps: [
          {
            ur: 'Approve karne se pehle pata, phone number aur tasweerein dekhein.',
            en: 'Check the address, the phone number and the photographs before approving.',
          },
          {
            ur: 'Phone number par ek baar call kar lena sab se sasta check hai.',
            en: 'One phone call to the listed number is the cheapest check there is.',
          },
        ],
      },
      {
        path: '/routes',
        title: 'Routes',
        purpose: {
          ur: 'Naam wale route jo tour aur Coster service ke liye istemal hote hain.',
          en: 'Named routes used for tours and Coster services.',
        },
        steps: [
          {
            ur: 'Agar route seat ke hisab se bikta hai to Pricing mein uska fixed per-seat fare bhi hona chahiye.',
            en: 'A route here should match a fixed per-seat fare in Pricing if it is sold by the seat.',
          },
        ],
      },
      {
        path: '/advisories',
        title: 'Road advisories',
        purpose: {
          ur: 'Driver aur customer dono ko dikhai jane wali warnings.',
          en: 'Warnings shown to Drivers and Customers.',
        },
        steps: [
          {
            ur: 'Road band hone ya land sliding ki tasdeeq hote hi foran lagayein.',
            en: 'Post closures and landslides as soon as they are confirmed.',
          },
          {
            ur: 'Khulte hi hata dein. Purani advisory logon ko sikha deti hai ke koi bhi advisory na parhein.',
            en: 'Remove them the moment they clear. A stale advisory trains people to ignore all of them.',
          },
        ],
      },
      {
        path: '/marketplace',
        title: 'Marketplace console',
        purpose: {
          ur: 'Alag console jahan tour operator apne package aur seats sambhalte hain. Yeh admin menu ka hissa nahi.',
          en: 'A separate console where tour operators manage their own packages and seats. Not part of the admin menu.',
        },
        steps: [
          {
            ur: 'Iska apna login hai. Admin yahan sirf tab jata hai jab kisi operator ki madad karni ho.',
            en: 'It has its own login. An admin goes here only to help an operator with what they are seeing.',
          },
          {
            ur: 'Jo package yahan se aate hain unki manzoori Tour packages mein hoti hai.',
            en: 'Packages submitted here are approved under Tour packages.',
          },
        ],
      },
    ],
  },

  // ----------------------------------------------------- pricing & money
  {
    label: 'PRICING & MONEY',
    blurb: {
      ur: 'Ek ride ki qeemat kaise banti hai, aur paisa kahan jata hai.',
      en: 'How a fare is built, and where the money goes.',
    },
    sections: [
      {
        path: '/pricing',
        title: 'Pricing & fares',
        purpose: {
          ur: 'Har gaari ka per-km rate aur minimum fare, aur us se tang qawaid.',
          en: 'The per-km rate and minimum fare for each vehicle, and any narrower rules.',
        },
        steps: [
          {
            ur: 'Upar wale grid mein har gaari ke liye do number rakhein: rate per km aur minimum fare. Yeh grid sirf City service ka hai.',
            en: 'Set two numbers per vehicle in the top grid: rate per km and minimum fare. This grid is the City service only.',
          },
          {
            ur: 'Base fare aur per-minute rate grid mein nahi hain — woh neeche "Pricing rules" ke andr har rule par set hote hain.',
            en: 'Base fare and the per-minute rate are not in the grid — they live on each rule under Pricing rules below.',
          },
          {
            ur: 'Hisab yeh hai: base fare + (per km × petrol index × road distance) + (per minute × waqt) = meter. Phir zone ka difficulty factor poore meter par lagta hai, aur zone ka return share distance wale hisse ka ek tukra isi difficulty ke sath jama karta hai. Aakhir mein natija minimum fare se neeche nahi jata — aur woh minimum bhi usi petrol index aur usi zone factor se barhta hai.',
            en: 'The sum is: base fare + (per km × fuel index × road distance) + (per minute × time) = the meter. The zone difficulty then multiplies that whole meter, and the zone’s return share adds a slice of the distance cost through the same difficulty. The result is floored at the minimum fare — and that minimum is itself scaled by the same fuel index and zone factor.',
          },
          {
            ur: 'Kisi tang cheez ke liye — weekend ka rate, ek shehar ka rate — neeche rule banayein jismein din aur ilaqa likha ho.',
            en: 'For anything narrower — a weekend rate, a rate for one town — add a rule below with days and an area.',
          },
          {
            ur: 'Fare preview se dekhein ke kaunsa rule lagta hai aur meter kya banta hai.',
            en: 'Use Fare preview to see which rule applies and what the meter comes to.',
          },
        ],
        cautions: [
          {
            ur: 'Rate per km aur minimum fare alag number hain. Minimum fare (maslan 1,600) ko per-km wale khane mein daalne se 12 km ka safar unees hazaar ka ban jata hai.',
            en: 'Rate per km and minimum fare are different numbers. Putting a minimum fare (say 1,600) into the per-km field prices a 12 km trip at nineteen thousand rupees.',
          },
          {
            ur: 'Sab se makhsoos active rule jeetta hai: ilaqa har jagah se upar, chhota ilaqa bare ilaqe se upar, aur likhe hue din har din se upar.',
            en: 'The most specific active rule wins: an area beats everywhere, a smaller area beats a larger one, named days beat every day.',
          },
          {
            ur: 'Tourism ki qeemat yahan nahi banti. Har driver apna tour rate Driver app mein khud rakhta hai.',
            en: 'Tourism is not priced here. Each Driver sets their own tour rate in the Driver app.',
          },
          {
            ur: 'Coster ke per-seat route fixed route fare par chalte hain, jo isi screen par set hota hai. Aise route par customer bid kar hi nahi sakta, aur us fare par na minimum lagta hai na petrol index.',
            en: 'Coster per-seat routes use fixed route fares, also set on this screen. On a listed route the Customer cannot bid at all, and that fare is subject to neither the minimum nor the fuel index.',
          },
          {
            ur: 'Fare preview sirf meter dikhata hai — us mein zone ka factor, return share, petrol index aur surge shamil nahi. Customer ka asal quote is se upar ho sakta hai, is liye isay aakhri qeemat na samjhein.',
            en: 'Fare preview shows the meter alone — it excludes the zone factor, the return share, the fuel index and surge. The Customer’s actual quote can be higher, so do not read it as the final price.',
          },
        ],
        roles: {
          ur: 'Parhna: zyadatar roles. Badalna: SuperAdmin, Admin, FinanceOfficer.',
          en: 'Read: most roles. Change: SuperAdmin, Admin, FinanceOfficer.',
        },
      },
      {
        path: '/fare-zones',
        title: 'Fare zones',
        purpose: {
          ur: 'Ilaqe ke hisab se sakhti — pahari raasta, kharab sarak, aur khali wapsi ka kharcha.',
          en: 'Terrain by area — hill roads, bad surfaces, and the cost of coming back empty.',
        },
        steps: [
          {
            ur: 'Zone kholein aur uske andar aane wale ilaqe daalein: har ilaqa ek point aur us ke gird kilometre ka daira hai.',
            en: 'Open a zone and add the areas inside it: each area is a point and a radius in kilometres around it.',
          },
          {
            ur: 'Difficulty factor poore fare ko barhata hai. Return share sirf distance wale hisse par lagta hai — yeh us wapsi ka kharcha hai jo khali aani hai.',
            en: 'The difficulty factor raises the whole fare. The return share applies only to the distance part — it pays for the leg that comes back empty.',
          },
          {
            ur: 'Screen par mojood effective multiplier dekhein: yeh dono factor mila kar asal asar dikhata hai, ek lambe (100 km) safar ke namoone par. Dono alag alag maamooli lagte hain — 1.30 difficulty aur 0.55 return share mil kar taqreeban do guna ban jate hain.',
            en: 'Watch the effective multiplier on the screen: it shows the two factors compounded, against a long (100 km) sample trip. Each looks modest on its own — 1.30 difficulty with a 0.55 return share comes to about 2×.',
          },
          {
            ur: 'Chhote shehri safar par yeh multiplier kam hota hai, kyunke waqt aur base fare wale hisse par return share nahi lagta.',
            en: 'On a short town trip the multiplier is lower, because the time and base-fare parts carry no return share.',
          },
          {
            ur: 'Naya zone banane ke baad usay inactive rakhein aur isi screen ka multiplier parh kar faisla karein. Pricing ka Fare preview zone ka asar nahi dikhata, is liye us se zone ki janch na karein.',
            en: 'Leave a new zone inactive and judge it by the multiplier on this screen. Fare preview under Pricing does not apply zones at all, so it cannot be used to check one.',
          },
        ],
        cautions: [
          {
            ur: 'Saat Kashmir zones pehle se mojood hain magar band hain, aur unke coordinates taqreeban hain. Active karne se pehle har ilaqe ka point map par milaein.',
            en: 'Seven Kashmir zones ship inactive with approximate coordinates. Check every area against the map before activating one.',
          },
          {
            ur: 'Active months sirf un maheenon mein zone chalata hai. Barfani raaston ke liye yeh sardi tak mehdood rakhna behtar hai.',
            en: 'Active months run a zone only in those months. For snow routes, keeping it to winter is usually right.',
          },
        ],
        roles: {
          ur: 'SuperAdmin, Admin, FinanceOfficer',
          en: 'SuperAdmin, Admin, FinanceOfficer',
        },
      },
      {
        path: '/fuel-prices',
        title: 'Fuel prices',
        purpose: {
          ur: 'Petrol aur diesel ki rozana qeemat, taake rate card apne aap pump ke sath chale.',
          en: 'Pump prices, so the rate card moves with fuel instead of going stale.',
        },
        steps: [
          {
            ur: 'Baseline woh qeemat hai jis par aap ka rate card durust tha. Jab tak baseline zero hai, petrol ka asar bilkul band hai.',
            en: 'The baseline is the pump price your rate card was correct at. While it is zero, fuel indexing is entirely off.',
          },
          {
            ur: 'Pehle aaj ki pump price record karein — jab tak ek qeemat mojood na ho, "Set to today’s prices" wala button screen par aata hi nahi.',
            en: 'Record today’s pump price first — the “Set to today’s prices” button does not appear until a price exists.',
          },
          {
            ur: 'Phir "Set to today’s prices" dabayein — is se indexing chalu hoti hai aur aaj ka fare bilkul wohi rehta hai jo kal tha.',
            en: 'Then press “Set to today’s prices” — that switches indexing on with today’s fares unchanged.',
          },
          {
            ur: 'Uske baad jab bhi OGRA qeemat badle, nayi qeemat record kar dein. Distance wala hissa khud us nisbat se hil jata hai.',
            en: 'After that, record the new price whenever OGRA revises it. The distance part of the fare moves by the same ratio on its own.',
          },
          {
            ur: 'Ek hi din dobara daalna usay theek karta hai, dusri entry nahi banata. Aane wali tareekh usi din se lagti hai.',
            en: 'Entering the same day twice corrects it rather than adding a second row, and a future date takes effect on that day.',
          },
        ],
        cautions: [
          {
            ur: 'Baseline barhane se distance wala hissa aur minimum fare kam ho jate hain, kam karne se barh jate hain. Base fare aur per-minute wala hissa bilkul nahi hilta, aur fixed per-seat route fare par petrol ka koi asar nahi.',
            en: 'Raising a baseline lowers the distance part and the minimum fare; lowering it raises them. The base fare and the per-minute part do not move at all, and fixed per-seat route fares are not indexed.',
          },
          {
            ur: 'Asar 0.85× se 1.25× ke darmiyan mehdood hai (yeh hadd Settings mein badli ja sakti hai), taake ek ghalat entry poore platform ki qeemat na badal de.',
            en: 'The index is capped between 0.85× and 1.25× — editable in Settings — so one bad row cannot reprice the platform.',
          },
        ],
        roles: {
          ur: 'SuperAdmin, Admin, FinanceOfficer',
          en: 'SuperAdmin, Admin, FinanceOfficer',
        },
      },
      {
        path: '/rate-insights',
        title: 'Route insights',
        purpose: {
          ur: 'Kis route par asal mein kitne ka soda hota hai, aur platform kitna bata raha hai.',
          en: 'What each route is actually agreed at, against what the platform suggests.',
        },
        steps: [
          {
            ur: 'Median agreed fare aur median suggested fare ka farq dekhein. Bara farq matlab suggestion ghalat jagah khari hai.',
            en: 'Compare the median agreed fare with the median suggested fare. A large gap means the suggestion is in the wrong place.',
          },
          {
            ur: '"No offer rate" asal ishara hai. Jis route par aadhi requests ko koi driver jawab hi nahi deta, wahan fare itna kam hai ke driver uthna nahi chahta.',
            en: 'The no-offer rate is the tell. A route where half the requests attract no offer at all is priced below what a driver will get out of bed for.',
          },
          {
            ur: 'Tabdeeli Pricing ya Fare zones mein karein — yeh screen sirf batati hai, badalti nahi.',
            en: 'Make the change in Pricing or Fare zones — this screen reports, it does not change anything.',
          },
        ],
        cautions: [
          {
            ur: 'Kam rides wale route ka median kuch sabit nahi karta. Pehle ginti dekhein, phir number.',
            en: 'A median over very few rides proves nothing. Read the ride count before the figure.',
          },
        ],
      },
      {
        path: '/finance',
        title: 'Finance & settlements',
        purpose: {
          ur: 'Driver ki kamai, payout, refund aur commission.',
          en: 'Driver earnings, payouts, refunds and commission.',
        },
        steps: [
          {
            ur: 'Payout purane se naye ki tarteeb mein karein.',
            en: 'Work payouts from oldest to newest.',
          },
          {
            ur: 'Refund approve karne se pehle usay uski booking se milaein.',
            en: 'Match a refund to its booking before approving it.',
          },
          {
            ur: 'Mukammal trips ka hisab thora thora kar ke barabar karein, ek bare dher mein nahi.',
            en: 'Reconcile completed trips regularly rather than in one large batch.',
          },
        ],
        cautions: [
          {
            ur: 'Refund asli paisa hai jo karobar se bahar ja raha hai. Pehle booking aur wajah dono tasdeeq karein.',
            en: 'A refund is real money leaving the business. Confirm the booking and the reason first.',
          },
          {
            ur: 'Reconcile, commission rules aur adjustments sirf SuperAdmin chala sakta hai. Admin ya FinanceOfficer ko in par 403 milta hai — button kharab nahi, ijazat nahi.',
            en: 'Reconciliation, commission rules and adjustments are SuperAdmin only. An Admin or FinanceOfficer gets a 403 on those — the button is not broken, the permission is missing.',
          },
        ],
        roles: {
          ur: 'Payout aur refund: SuperAdmin, Admin, FinanceOfficer. Reconcile aur commission: sirf SuperAdmin.',
          en: 'Payouts and refunds: SuperAdmin, Admin, FinanceOfficer. Reconciliation and commission: SuperAdmin only.',
        },
      },
      {
        path: '/payments',
        title: 'Legacy payments',
        purpose: {
          ur: 'Purana payment record — receipts, nakaam transactions aur controlled refund.',
          en: 'The older payment record — receipts, failures and controlled refunds.',
        },
        steps: [
          {
            ur: 'Purani booking ki tehqeeq ke liye istemal karein. Naya kaam Finance & settlements mein hota hai.',
            en: 'Use it when investigating an older booking. New work belongs in Finance & settlements.',
          },
          {
            ur: 'Status badalte waqt review notes zaroor likhein — yeh baad mein wahi record hai jo parha jata hai.',
            en: 'Write review notes whenever you change a status — they are what gets read later.',
          },
        ],
        roles: {
          ur: 'SuperAdmin, Admin, FinanceOfficer',
          en: 'SuperAdmin, Admin, FinanceOfficer',
        },
      },
    ],
  },

  // ------------------------------------------------------ trust & safety
  {
    label: 'TRUST & SAFETY',
    blurb: {
      ur: 'Jab kuch ghalat ho jaye.',
      en: 'When something goes wrong.',
    },
    sections: [
      {
        path: '/safety',
        title: 'Safety incidents',
        purpose: {
          ur: 'Dono apps se aane wale SOS alerts aur incidents.',
          en: 'SOS alerts and incidents raised from either app.',
        },
        steps: [
          {
            ur: 'Har alert ko asli samjhein jab tak kisi se baat na ho jaye.',
            en: 'Treat every alert as real until you have spoken to someone.',
          },
          {
            ur: 'Pehle customer ko phone karein, phir driver ko.',
            en: 'Phone the Customer first, then the Driver.',
          },
          {
            ur: 'Jo kiya aur jab kiya, likh dein. Baad mein jo bhi review hoga woh yehi log parhega.',
            en: 'Record what you did and when. The log is what any later review reads.',
          },
        ],
        cautions: [
          {
            ur: 'Yeh qatar poore portal mein sab se pehle aati hai.',
            en: 'This queue comes before everything else in the portal.',
          },
        ],
      },
      {
        path: '/disputes',
        title: 'Complaints & disputes',
        purpose: {
          ur: 'Trip, fare ya rawaiye par ikhtilaf.',
          en: 'Disagreements about a trip, a fare or conduct.',
        },
        steps: [
          {
            ur: 'Dono taraf ki baat sunne se pehle booking ki status history parhein.',
            en: 'Read the booking status history before either account of events.',
          },
          {
            ur: 'Dono se poochein. Ek tarfa faisla doosri shikayat paida karta hai.',
            en: 'Ask both sides. A one-sided decision produces a second dispute.',
          },
          {
            ur: 'Natija aise likhein ke agla parhne wala aap se poochhe baghair wajah samajh jaye.',
            en: 'Write the outcome so the next person reading it understands the reasoning without asking you.',
          },
        ],
      },
      {
        path: '/support',
        title: 'Support tickets',
        purpose: {
          ur: 'Woh sab jo na incident hai na dispute.',
          en: 'Everything that is not an incident or a dispute.',
        },
        steps: [
          {
            ur: 'Ticket kholne se pehle booking ya user dhoondein.',
            en: 'Find the booking or user before opening a ticket.',
          },
          {
            ur: 'Masla, waqt, screen aur jo pehle azmaya gaya — chaaron likhein.',
            en: 'Record the exact problem, the time, the screen and what was already tried.',
          },
        ],
        cautions: [
          {
            ur: 'Technical error ka matn kabhi customer ya driver ko na parh kar sunayein. Unki zaban mein masla bata kar upar bhejein.',
            en: 'Never read technical error text to a Customer or Driver. Describe the problem in their terms and escalate.',
          },
        ],
      },
    ],
  },

  // ------------------------------------------------------------ reports
  {
    label: 'REPORTS',
    blurb: {
      ur: 'Ginti, hisaab, aur kis ne kya kiya.',
      en: 'Figures, reconciliation, and who did what.',
    },
    sections: [
      {
        path: '/executive-operations',
        title: 'Executive operations',
        purpose: {
          ur: 'Is waqt chalti hui tamam rides aur tours, har das second mein taza.',
          en: 'Every active ride and tour, refreshed every ten seconds.',
        },
        steps: [
          {
            ur: 'Poore platform ki ek screen par soorat-e-haal dekhne ke liye — bina kisi record ko khole.',
            en: 'Read the whole platform on one screen, without opening any record.',
          },
          {
            ur: 'Tracking ka khana "Stale" dikhaye to us trip ka GPS ruka hua hai; kaam Operations & dispatch par hoga.',
            en: 'A “Stale” tracking cell means that trip’s GPS has stopped; the work happens in Operations & dispatch.',
          },
        ],
      },
      {
        path: '/reports',
        title: 'Reports & reconciliation',
        purpose: {
          ur: 'Kisi arse ka total — hisaab ke liye aur faislon ke liye.',
          en: 'Totals for a period, for accounting and for decisions.',
        },
        steps: [
          {
            ur: 'Pehle arsa chunein; screen ka har number usi ke peeche chalta hai.',
            en: 'Pick the period first; every figure on the page follows it.',
          },
          {
            ur: 'Arsa badalne se pehle export kar lein, taake jo number aap ne bataye woh dobara nikale ja sakein.',
            en: 'Export before a period is edited, so the numbers you quoted can be reproduced.',
          },
        ],
      },
      {
        path: '/audit',
        title: 'Audit log',
        purpose: {
          ur: 'Is portal mein kis ne kya kiya.',
          en: 'Who did what in this portal.',
        },
        steps: [
          {
            ur: 'Kisi saathi se poochne se pehle yahan dekhein — jawab aksar yahin hota hai.',
            en: 'Check it before asking a colleague what happened — the answer is usually here.',
          },
        ],
      },
    ],
  },

  // -------------------------------------------------------------- setup
  {
    label: 'SETUP',
    blurb: {
      ur: 'Woh settings jo ek baar theek kar ke chhor di jati hain.',
      en: 'The settings you configure once and leave alone.',
    },
    sections: [
      {
        path: '/services',
        title: 'Services',
        purpose: {
          ur: 'Kisi service ko customer ke liye band karna, bina driver se chhupaye.',
          en: 'Turn a service off for customers without hiding it from drivers.',
        },
        steps: [
          {
            ur: 'Jo service abhi shuru nahi hui usay off kar dein — customer ki app mein uska tile dhundla ho jata hai aur us par aap ka rakha hua badge lagta hai (default "SOON").',
            en: 'Switch off a service that has not launched — its tile dims in the customer app and carries whatever badge you set (the default is “SOON”).',
          },
          {
            ur: 'Apna closed message likhein. Wohi paighaam customer ko tile chhoone par dikhta hai, is liye usay saaf likhein.',
            en: 'Write your own closed message. That is what the customer sees on tapping the tile, so write it plainly.',
          },
        ],
        cautions: [
          {
            ur: 'Yeh switch sirf customer app ka darwaza band karta hai. Driver app par koi asar nahi, chalti hui bookings bhi nahi rukteen, aur server khud aisi service ki booking rad nahi karta — is liye isay technical rok na samjhein.',
            en: 'This switch closes the door in the customer app only. It does not touch the driver app, it does not end trips already running, and the server itself does not refuse bookings for a closed service — so do not treat it as a technical block.',
          },
        ],
      },
      {
        path: '/notifications',
        title: 'Notifications',
        purpose: {
          ur: 'Customer ya driver ko bheje jane wale paighamaat.',
          en: 'Messages sent to Customers or Drivers.',
        },
        steps: [
          {
            ur: 'Paighaam likhein, audience chunein, aur bhejne se pehle ek baar aur parhein.',
            en: 'Write the message, choose the audience, and read it once more before sending.',
          },
        ],
        cautions: [
          {
            ur: 'Notification wapas nahi li ja sakti. Har banday ke phone par pohanch jati hai.',
            en: 'A notification cannot be recalled. Every recipient sees it on their phone.',
          },
        ],
      },
      {
        path: '/settings',
        title: 'Settings',
        purpose: {
          ur: 'Portal aur platform ki configuration.',
          en: 'Portal and platform configuration.',
        },
        steps: [
          {
            ur: 'Ek waqt mein ek cheez badlein aur asar dekh kar agli badlein.',
            en: 'Change one thing at a time and check the effect before changing the next.',
          },
          {
            ur: 'Pricing wali settings ka asar agli quote par aata hai — ek minute ke andar, portal restart kiye baghair.',
            en: 'Pricing settings take effect on the next quote — within a minute, with nothing to restart.',
          },
        ],
      },
      {
        path: '/places',
        title: 'Map places',
        purpose: {
          ur: 'Naam wale pickup aur drop points jo customer search kar sakta hai.',
          en: 'Named pickup and drop points Customers can search.',
        },
        steps: [
          {
            ur: 'Wohi jagahein daalein jinka naam log lete hain — bus stand, hospital, mashhoor bazaar.',
            en: 'Add the places people actually name — bus stands, hospitals, well-known markets.',
          },
          {
            ur: 'Coordinates map par set karein, type kar ke nahi, taake pin wahan lage jahan gaari ruk sake.',
            en: 'Set the coordinates on the map, not by typing them, so the pin lands where a vehicle can stop.',
          },
        ],
      },
      {
        path: '/appearance',
        title: 'Address search',
        purpose: {
          ur: 'Woh Google key jo From / To ke autocomplete aur pata dhoondne ke liye chalti hai.',
          en: 'The Google key used for From / To autocomplete and reverse geocoding.',
        },
        steps: [
          {
            ur: 'Key badalne ke baad save karein aur app mein ek pata type kar ke dekh lein.',
            en: 'Save after changing the key, then type one address in the app to confirm it works.',
          },
        ],
        cautions: [
          {
            ur: 'Ghalat ya khatam shuda key se search band nahi hoti — woh chupke se OpenStreetMap par chali jati hai, jo Pakistan ke zyadatar colony, sector aur gali ke naam nahi janta. Natija yeh ke search kharab ho jati hai, band nahi hoti, aur kisi ko shikayat aane tak pata nahi chalta.',
            en: 'A wrong or expired key does not stop search — it silently falls back to OpenStreetMap, which does not know most Pakistani colony, sector and street names. Results get worse rather than stopping, so nobody notices until a complaint arrives.',
          },
        ],
        roles: {
          ur: 'Parhna: SuperAdmin, Admin, Operations. Badalna: sirf SuperAdmin.',
          en: 'Read: SuperAdmin, Admin, Operations. Change: SuperAdmin only.',
        },
      },
      {
        path: '/data-management',
        title: 'Data management',
        purpose: {
          ur: 'Bohot saare record ek sath badalne wale kaam.',
          en: 'Bulk data operations.',
        },
        steps: [
          {
            ur: 'Import se pehle export karein. Chalane se pehle parhein ke job kya badlega.',
            en: 'Export before you import. Read what a job will change before running it.',
          },
        ],
        cautions: [
          {
            ur: 'Yahan ke kaam ek sath bohot se record par lagte hain aur hamesha wapas nahi liye ja sakte.',
            en: 'Actions here affect many records at once and are not always reversible.',
          },
        ],
        roles: { ur: 'SuperAdmin, Admin', en: 'SuperAdmin, Admin' },
      },
      {
        path: '/diagnostics',
        title: 'Diagnostics',
        purpose: {
          ur: 'API, database aur maps theek chal rahe hain ya nahi.',
          en: 'Whether the API, database and maps are healthy.',
        },
        steps: [
          {
            ur: 'Jab kai screens ek sath kharab lagein to sab se pehle yahan dekhein. Ek cheez kharab hone se kai screens tooti hui lagti hain.',
            en: 'Check here first when several screens misbehave at once. One failing dependency looks like many broken screens.',
          },
        ],
      },
      {
        path: '/help',
        title: 'Help / How to use',
        purpose: {
          ur: 'Yehi guide, poori, shuru se aakhir tak parhne ke liye.',
          en: 'This guide, in full, for reading end to end.',
        },
        steps: [
          {
            ur: 'Upar Roman / English ka switch hai. Jo zaban chunein ge woh isi browser mein yaad rehti hai.',
            en: 'The Roman / English switch is at the top. Your choice is remembered in this browser.',
          },
          {
            ur: 'Search dono zabanon mein chalti hai — "refund" likhein ya "wapsi", dono se wohi hissa milega.',
            en: 'Search reads both languages — type “refund” or “wapsi” and the same section comes back.',
          },
          {
            ur: 'Yehi guide har screen par upar dayein "Guide" button ke peeche bhi hai, taake kaam chhore baghair dekha ja sake.',
            en: 'The same guide sits behind the Guide button on every screen, so you never have to leave what you are doing.',
          },
        ],
      },
    ],
  },
];
