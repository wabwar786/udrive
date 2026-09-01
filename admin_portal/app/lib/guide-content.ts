/**
 * The admin guide, module by module.
 *
 * Kept as data in its own file rather than markup inside a page, for two
 * reasons. The guide is read by people learning the portal, and it has to say
 * the same thing in the Guide button, the Help page and anywhere it is
 * surfaced later — three copies would disagree within a month. And an admin who
 * needs to correct a step should be able to find one sentence and change it,
 * without touching a component.
 *
 * Every entry names the exact screen it describes, so a reader can put the
 * guide beside the portal and follow along rather than translating.
 *
 * The rules are written plainly, including the unflattering ones. A guide that
 * only lists happy paths teaches people to be surprised.
 */

export type GuideSection = {
  /** The route this section documents, so it can link straight there. */
  path: string;
  title: string;
  /** One line: what this screen is for. */
  purpose: string;
  /** What an admin actually does here, in order. */
  steps: string[];
  /** Things that are easy to get wrong, or that cannot be undone. */
  cautions?: string[];
  /** Who is allowed to act here. */
  roles?: string;
};

export type GuideGroup = {
  label: string;
  blurb: string;
  sections: GuideSection[];
};

export const guideGroups: GuideGroup[] = [
  {
    label: 'Start here',
    blurb:
      'What the portal is, how a booking moves through it, and the rules that ' +
      'apply everywhere.',
    sections: [
      {
        path: '/',
        title: 'How a ride actually flows',
        purpose:
          'The path every ride takes, so you know which screen owns which stage.',
        steps: [
          'A Customer sets a pickup and destination, picks a vehicle, and names a fare. That creates a ride request — visible under Ride requests.',
          'Drivers within range see it and answer with their own fare. Each answer is a Driver offer.',
          'The Customer accepts one offer. That creates a booking and assigns the Driver — visible under Bookings.',
          'The Driver drives to the pickup, takes the trip OTP from the Customer, and starts the trip. Progress is under Operations & dispatch and Live tracking.',
          'The trip completes, money settles under Finance, and either side may leave a rating.',
        ],
        cautions: [
          'A ride request is not a booking. Cancelling a request costs nothing; cancelling a booking affects a Driver who has already committed and may already be driving.',
          'The Customer names the fare and the Driver answers it. The admin sets the rate that seeds that first figure — never the final price of an individual ride.',
        ],
      },
      {
        path: '/',
        title: 'Overview',
        purpose: 'The day at a glance, and what is waiting for someone.',
        steps: [
          'Read the headline counts first — active trips, pending verifications, open disputes.',
          'Anything with a number that should be zero is your queue for the day.',
          'Open the record before acting. Never act from a dashboard count alone.',
        ],
      },
      {
        path: '/',
        title: 'Roles and what each can do',
        purpose:
          'The portal restricts by role. Knowing yours saves guessing at a locked button.',
        steps: [
          'SuperAdmin — everything, including deletion and commission rules.',
          'Admin — everything operational: verification, pricing, disputes, refunds.',
          'Manager and Operations — day-to-day dispatch, bookings, support. Read access to money.',
          'FinanceOfficer — payouts, refunds, reconciliation, and pricing rates.',
          'SupportAgent — tickets and lookups. No money, no verification.',
        ],
        cautions: [
          'A button that does nothing usually means your role cannot do it, not that the portal is broken. Check with whoever holds the higher role rather than retrying.',
        ],
      },
    ],
  },

  {
    label: 'Operations',
    blurb: 'Live rides, requests and the dispatch desk.',
    sections: [
      {
        path: '/ride-requests',
        title: 'Ride requests',
        purpose:
          'Customers who are asking for a ride but do not have one yet.',
        steps: [
          'Watch the offers count. A request sitting at zero offers means no Driver has taken the fare.',
          'Repeated zero-offer requests in one area usually mean the per-km rate there is too low, or nobody is online. Check Pricing and the online Driver count before assuming a fault.',
          'Requests expire on their own. There is nothing to clean up.',
        ],
      },
      {
        path: '/bookings',
        title: 'Bookings',
        purpose: 'Rides that have a Driver. This is the record of the trip.',
        steps: [
          'Search by booking reference, Customer name or phone.',
          'Open a booking to see the fare, the Driver, the vehicle and the full status history.',
          'The status history is the truth about what happened and when. Read it before believing either side of a dispute.',
        ],
        cautions: [
          'Cancelling here affects a real Driver who may already be driving. Record why.',
        ],
      },
      {
        path: '/operations',
        title: 'Operations & dispatch',
        purpose: 'The desk for trips in progress.',
        steps: [
          'Sort by last activity. The oldest untouched trip is the one most likely to be in trouble.',
          'A trip stuck at DriverEnRoute with no GPS for several minutes needs a phone call, not a status change.',
          'Change a status by hand only when you have spoken to someone and know the real state.',
        ],
        cautions: [
          'Forcing a status hides the problem instead of fixing it. The Driver app will keep reporting what it sees.',
        ],
      },
      {
        path: '/live-tracking',
        title: 'Live tracking',
        purpose: 'Where the vehicles are right now.',
        steps: [
          'Stale markers mean the Driver app has stopped reporting — usually signal, sometimes a closed app.',
          'Use it to answer "where is my ride" calls without phoning the Driver mid-drive.',
        ],
      },
      {
        path: '/packages',
        title: 'Tour packages',
        purpose: 'Multi-day tour products offered by Drivers.',
        steps: [
          'Review a package before it goes live: route, seats, price, what is included.',
          'Tour pricing is set by each Driver on their own vehicle, not here.',
        ],
      },
    ],
  },

  {
    label: 'People & fleet',
    blurb: 'Who is allowed to drive, and in what.',
    sections: [
      {
        path: '/verification',
        title: 'Verification',
        purpose:
          'Approving Drivers and vehicles. The most consequential screen in the portal.',
        steps: [
          'Open the submission and check every document against the person: CNIC, licence, registration.',
          'Confirm the licence has not expired and the name matches the CNIC.',
          'Confirm the vehicle registration matches the vehicle photographs.',
          'Approve, or reject with a reason the Driver can act on.',
        ],
        cautions: [
          'An approval puts a stranger in a car with a Customer. Rejecting a good application costs a Driver a day; approving a bad one costs someone much more.',
          '"Rejected" with no reason is not a decision, it is a wall. Write what has to be fixed.',
          'A Driver cannot appear on any Customer map until both the Driver is Approved and the vehicle is Verified.',
        ],
        roles: 'SuperAdmin, Admin',
      },
      {
        path: '/drivers',
        title: 'Drivers',
        purpose: 'The Driver roster, their standing and their history.',
        steps: [
          'Use it to look up a Driver during a complaint or a support call.',
          'Suspension takes a Driver offline immediately and stops new requests reaching them.',
        ],
        cautions: [
          'Suspension is not a warning. It removes someone’s income that day. Use the disputes process for anything short of a safety concern.',
        ],
      },
      {
        path: '/vehicles',
        title: 'Vehicles and vehicle pictures',
        purpose:
          'The fleet, and the photographs Customers see when choosing a vehicle.',
        steps: [
          'Upload one clear photograph per category: Car, Bike, Coster, Hiace.',
          'Use the same style for all four — same angle, same background — or the picker looks assembled from different apps.',
          'A category with no photograph falls back to a plain icon in the app.',
        ],
        cautions: [
          'This is what the Customer judges the vehicle by. A dark or cropped photograph makes a good vehicle look worse than it is.',
        ],
      },
      {
        path: '/customers',
        title: 'Users & access',
        purpose: 'Customer accounts and portal staff accounts.',
        steps: [
          'Create staff accounts with the lowest role that lets them do their job.',
          'Remove access the day someone leaves, not at the end of the month.',
        ],
      },
    ],
  },

  {
    label: 'Money',
    blurb: 'What a ride costs, and where the money goes.',
    sections: [
      {
        path: '/pricing',
        title: 'Pricing & fares',
        purpose:
          'The per-kilometre rate Customers are quoted, and any narrower rules.',
        steps: [
          'Set the standard rate for each vehicle in the top grid: rate per km, and a minimum fare.',
          'A trip is priced: rate per km × road distance, plus a small per-minute amount, and never below the minimum.',
          'For anything narrower — a weekend rate, a rate for one town — add a rule below with days and an area.',
          'Use Fare preview before saving. Enter a distance, a time and an area and it shows exactly what a Customer would be quoted, and which rule produced it.',
        ],
        cautions: [
          'Rate per km and minimum fare are different numbers. Putting a minimum fare (say 1,600) into the per-km field prices a 12 km trip at nineteen thousand rupees.',
          'The most specific active rule wins: an area beats everywhere, a smaller area beats a larger one, named days beat every day.',
          'Tourism is not priced here. Each Driver sets their own tour rate in the Driver app.',
          'Coster per-seat routes use fixed route fares, also set on this screen. On a listed route the Customer cannot bid at all.',
        ],
        roles: 'Read: most roles. Change: SuperAdmin, Admin, FinanceOfficer.',
      },
      {
        path: '/finance',
        title: 'Finance & settlements',
        purpose: 'Driver earnings, payouts, refunds and commission.',
        steps: [
          'Work payouts from oldest to newest.',
          'Match a refund to its booking before approving it.',
          'Reconcile completed trips regularly rather than in one large batch.',
        ],
        cautions: [
          'A refund is real money leaving the business. Confirm the booking and the reason first.',
        ],
        roles: 'SuperAdmin, Admin, FinanceOfficer',
      },
      {
        path: '/reports',
        title: 'Reports & reconciliation',
        purpose: 'Totals for a period, for accounting and for decisions.',
        steps: [
          'Pick the period first; every figure on the page follows it.',
          'Export before a period is edited, so the numbers you quoted can be reproduced.',
        ],
      },
    ],
  },

  {
    label: 'Trust & safety',
    blurb: 'When something goes wrong.',
    sections: [
      {
        path: '/safety',
        title: 'Safety incidents',
        purpose: 'SOS alerts and incidents raised from either app.',
        steps: [
          'Treat every alert as real until you have spoken to someone.',
          'Phone the Customer first, then the Driver.',
          'Record what you did and when. The log is what any later review reads.',
        ],
        cautions: [
          'This queue comes before everything else on this page.',
        ],
      },
      {
        path: '/disputes',
        title: 'Complaints & disputes',
        purpose: 'Disagreements about a trip, a fare or conduct.',
        steps: [
          'Read the booking status history before either account of events.',
          'Ask both sides. A one-sided decision produces a second dispute.',
          'Write the outcome so the next person reading it understands the reasoning without asking you.',
        ],
      },
      {
        path: '/support',
        title: 'Support tickets',
        purpose: 'Everything that is not an incident or a dispute.',
        steps: [
          'Find the booking or user before opening a ticket.',
          'Record the exact problem, the time, the screen and what was already tried.',
        ],
        cautions: [
          'Never read technical error text to a Customer or Driver. Describe the problem in their terms and escalate.',
        ],
      },
      {
        path: '/audit',
        title: 'Audit log',
        purpose: 'Who did what in this portal.',
        steps: [
          'Check it before asking a colleague what happened — the answer is usually here.',
        ],
      },
    ],
  },

  {
    label: 'Places & content',
    blurb: 'What Customers see when they search and browse.',
    sections: [
      {
        path: '/places',
        title: 'Map places',
        purpose: 'Named pickup and drop points Customers can search.',
        steps: [
          'Add the places people actually name — bus stands, hospitals, well-known markets.',
          'Set the coordinates on the map, not by typing them, so the pin lands where a vehicle can stop.',
        ],
      },
      {
        path: '/destinations',
        title: 'Destinations',
        purpose: 'Tourism destinations shown in Explore.',
        steps: [
          'Keep photographs current. An out-of-season photograph sets the wrong expectation.',
        ],
      },
      {
        path: '/routes',
        title: 'Routes',
        purpose: 'Named routes used for tours and Coster services.',
        steps: [
          'A route here should match a fixed per-seat fare in Pricing if it is sold by the seat.',
        ],
      },
      {
        path: '/advisories',
        title: 'Road advisories',
        purpose: 'Warnings shown to Drivers and Customers.',
        steps: [
          'Post closures and landslides as soon as they are confirmed.',
          'Remove them the moment they clear. A stale advisory trains people to ignore all of them.',
        ],
      },
      {
        path: '/hotels',
        title: 'Hotels & approvals',
        purpose: 'Hotel listings and the owners who submit them.',
        steps: [
          'Check the address, the phone number and the photographs before approving.',
        ],
      },
      {
        path: '/notifications',
        title: 'Notifications',
        purpose: 'Messages sent to Customers or Drivers.',
        steps: [
          'Write the message, choose the audience, and read it once more before sending.',
        ],
        cautions: [
          'A notification cannot be recalled. Every recipient sees it on their phone.',
        ],
      },
    ],
  },

  {
    label: 'System',
    blurb: 'Configuration and health.',
    sections: [
      {
        path: '/settings',
        title: 'Settings',
        purpose: 'Portal and platform configuration.',
        steps: [
          'Change one thing at a time and check the effect before changing the next.',
        ],
      },
      {
        path: '/diagnostics',
        title: 'Diagnostics',
        purpose: 'Whether the API, database and maps are healthy.',
        steps: [
          'Check here first when several screens misbehave at once. One failing dependency looks like many broken screens.',
        ],
      },
      {
        path: '/data-management',
        title: 'Data management',
        purpose: 'Bulk data operations.',
        steps: [
          'Export before you import. Read what a job will change before running it.',
        ],
        cautions: [
          'Actions here affect many records at once and are not always reversible.',
        ],
        roles: 'SuperAdmin',
      },
    ],
  },
];
