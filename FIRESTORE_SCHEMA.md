# DUSUQ — Multi-Tenant Firestore Schema

## Design principle
Single flat collection per data type, shared schema across all tenants, with an
immutable `orgId` field on every document. This avoids Firestore's subcollection
fan-out complexity (you'd otherwise need `organizations/{orgId}/animals/{id}` nesting,
which makes SuperAdmin cross-org aggregate queries painful — you'd have to query every
org's subcollection separately). A flat `animals` collection with `orgId` lets a
SuperAdmin run one query across all orgs, while security rules block everyone else
from doing the same.

---

## `users/{uid}`
Document ID = Firebase Auth UID. This is the source of truth security rules check
against — NOT custom claims alone, because claims require a token refresh to propagate
(up to 1hr delay or a forced `getIdToken(true)`), while a Firestore read is immediate.
We set custom claims too (for fast client-side role checks) but rules trust this doc.

```
users/{uid}
  ├─ uid:        string   (matches doc id, redundant but useful for queries)
  ├─ orgId:      string   (immutable after creation; "" only for SuperAdmin)
  ├─ role:       string   enum: "SuperAdmin" | "OrgAdmin" | "Farmer"
  ├─ email:      string
  ├─ phone:      string | null
  ├─ displayName:string
  ├─ status:     string   enum: "active" | "invited" | "disabled"
  ├─ invitedBy:  string   (uid of inviter, null for first OrgAdmin/SuperAdmin)
  ├─ createdAt:  timestamp
  └─ lastLoginAt:timestamp
```

## `organizations/{orgId}`
```
organizations/{orgId}
  ├─ name:          string   ("Khanewal Dairy Cooperative")
  ├─ ownerUid:       string   (the OrgAdmin who owns this org)
  ├─ planTier:       string   enum: "trial" | "basic" | "pro"
  ├─ animalCount:    number   (denormalized counter, updated via Cloud Function)
  ├─ status:         string   enum: "active" | "suspended"
  ├─ createdAt:      timestamp
  └─ settings:
       ├─ currency:        string  ("PKR")
       └─ defaultLanguage: string  ("ur" | "en")
```

## `animals/{animalId}`  (and identically-shaped milk_records, feed_expenses,
## breeding_records, medical_records, finance_records)
```
animals/{animalId}
  ├─ orgId:       string   ← REQUIRED, IMMUTABLE, set once at creation, never updated
  ├─ tagNumber:   string
  ├─ breed:       string
  ├─ sex:         string
  ├─ status:      string
  ├─ createdBy:   string   (uid — useful for audit trail, who entered this record)
  ├─ createdAt:   timestamp
  └─ ...module-specific fields (unchanged from existing MVP models)
```

**The only schema change to your 5 existing collections is adding `orgId` and
`createdBy` to every document.** Everything else (Animal, MilkRecord, FeedExpense,
BreedingRecord, MedicalRecord models) stays as already built.

---

## Why `orgId` lives on every document instead of subcollections

| | Flat + orgId field | Subcollections per org |
|---|---|---|
| SuperAdmin "all farms" query | 1 query, `where('orgId', 'in', [...])` or no filter | N queries, one per org |
| Per-farm security rule | 1 rule pattern, reused on every collection | Same, but path-dependent |
| Adding a new org | Zero schema change | New subcollection path |
| Composite indexes | `orgId + date`, `orgId + animalId` — small set | Same indexes, but isolated per org |

Flat collections win for a SaaS product where SuperAdmin (you) needs cross-tenant
visibility for the investor-facing aggregate dashboard.

---

## Required composite indexes (add these to `firestore.indexes.json`)

| Collection | Fields |
|---|---|
| `animals` | `orgId` ASC, `status` ASC |
| `milk_records` | `orgId` ASC, `date` DESC |
| `milk_records` | `orgId` ASC, `animalId` ASC, `date` DESC |
| `feed_expenses` | `orgId` ASC, `date` DESC |
| `breeding_records` | `orgId` ASC, `animalId` ASC, `breedingDate` DESC |
| `breeding_records` | `orgId` ASC, `expectedCalvingDate` ASC |
| `medical_records` | `orgId` ASC, `animalId` ASC, `date` DESC |
| `finance_records` | `orgId` ASC, `date` DESC |
| `users` | `orgId` ASC, `status` ASC |
