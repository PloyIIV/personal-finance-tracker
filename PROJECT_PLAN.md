# แผนโปรเจกต์: AI-Powered Personal Finance & Receipt Tracker

## เป้าหมาย
สร้างเว็บแอปสำหรับบันทึกรายรับ–รายจ่ายส่วนบุคคล ดูภาพรวมการเงิน ตั้งงบรายหมวด และลดการกรอกข้อมูลด้วยการสแกนใบเสร็จ/สลิปด้วย AI โดยผู้ใช้ตรวจทานข้อมูลก่อนบันทึกทุกครั้ง

## ขอบเขต MVP

1. **บัญชีผู้ใช้** — สมัคร/เข้าสู่ระบบด้วย Supabase Auth และจัดการข้อมูลแยกตามผู้ใช้
2. **รายการธุรกรรม** — เพิ่ม/แก้ไข/ลบรายรับและรายจ่าย ระบุจำนวนเงิน วันที่ หมวดหมู่ บันทึกช่วยจำ และแหล่งที่มา
3. **Dashboard** — ยอดรับ ยอดจ่าย ยอดสุทธิของเดือนที่เลือก, กราฟรายรับเทียบรายจ่ายรายวัน/รายเดือน และสรุปยอดตามหมวดหมู่
4. **Receipt Scanner** — อัปโหลดรูป เก็บใน Supabase Storage แบบ private ส่งภาพให้ Gemini ผ่าน server route แล้วแสดงข้อมูลที่อ่านได้ในฟอร์มแก้ไขก่อนยืนยัน
5. **งบประมาณและเตือน** — ตั้งงบรายเดือนต่อหมวด แสดงยอดใช้ไป/คงเหลือ และสถานะเตือนเมื่อถึง 80% และ 100%
6. **มือถือและการเข้าถึง** — ใช้งานได้บนจอเล็ก ฟอร์มมี label, validation และสถานะ loading/error ชัดเจน

**ยังไม่รวมใน MVP:** เชื่อมบัญชีธนาคาร, OCR แบบ realtime, การแชร์ครอบครัว, recurring transactions, push notification และคำแนะนำทางการเงินจาก AI

## เส้นทางผู้ใช้หลัก

1. สมัคร/เข้าสู่ระบบ → ตั้งสกุลเงินและหมวดหมู่เริ่มต้น
2. Dashboard เปิดเดือนปัจจุบัน → เพิ่มธุรกรรมเองหรือกดสแกนใบเสร็จ
3. สแกน: เลือกภาพ → ตรวจชนิด/ขนาดไฟล์ → อัปโหลด private → วิเคราะห์ → แสดงยอด ร้านค้า วันที่ และหมวดที่คาดเดาพร้อมความมั่นใจ → ผู้ใช้แก้ไข/ยืนยัน → บันทึกเป็นธุรกรรม
4. ตั้งงบต่อหมวด → Dashboard แสดงการใช้เทียบงบและเตือนเมื่อผ่าน threshold

หาก AI อ่านไม่ครบหรือไม่แน่ใจ ให้ผู้ใช้แก้ฟอร์มได้เสมอ ห้ามสร้างธุรกรรมอัตโนมัติโดยไม่มีการยืนยัน

## สถาปัตยกรรมที่เสนอ

- **เว็บ:** Next.js App Router + TypeScript, Tailwind CSS, shadcn/ui, React Hook Form + Zod
- **ข้อมูล/ตัวตน/ไฟล์:** Supabase Auth, PostgreSQL, Storage bucket แบบ private และ Row Level Security (RLS)
- **AI:** เรียก Gemini จาก Next.js Route Handler ฝั่ง server เท่านั้น ไม่ส่ง API key ไป browser
- **การอ่านภาพ:** Route ตรวจสิทธิ์และชนิด/ขนาดไฟล์ → โหลดภาพจาก private storage หรือรับไฟล์ผ่านช่องทางที่ปลอดภัย → เรียก Gemini ด้วย prompt ที่บังคับผลลัพธ์ JSON ตาม schema → validate ฝั่ง server → ส่งเฉพาะผลที่ผ่าน validation กลับ client
- **การคำนวณยอด:** คำนวณจากธุรกรรมที่ยืนยันแล้วในฐานข้อมูล; dashboard query ตาม user, ช่วงวันที่ และหมวดหมู่
- **การ deploy:** Vercel สำหรับ Next.js และ Supabase สำหรับบริการ backend; secrets อยู่ใน environment variables ฝั่ง server

## โครงสร้างข้อมูลหลัก

| ตาราง | ฟิลด์สำคัญ | ข้อกำหนด |
|---|---|---|
| `profiles` | `id`, `display_name`, `currency`, `timezone` | `id` อ้างถึง `auth.users.id` |
| `categories` | `id`, `user_id`, `name`, `type`, `color`, `icon`, `is_default` | `type` เป็น income/expense; หมวดกำหนดเองเป็นของผู้ใช้ |
| `transactions` | `id`, `user_id`, `category_id`, `type`, `amount`, `currency`, `occurred_at`, `note`, `merchant`, `source`, `receipt_id` | `amount` เป็น numeric แบบบวก; `source` manual/receipt; เก็บเวลาอย่างสม่ำเสมอ |
| `receipts` | `id`, `user_id`, `storage_path`, `status`, `extracted_data`, `confidence`, `created_at` | สถานะ uploaded/processing/reviewed/failed; metadata ไม่เปิดสู่สาธารณะ |
| `budgets` | `id`, `user_id`, `category_id`, `month`, `limit_amount` | unique ต่อ user + category + month |

ใช้ UUID, foreign keys, index ที่เหมาะสม (`user_id, occurred_at`, `user_id, category_id`) และตรวจ constraint ของ amount/type/date ในฐานข้อมูลด้วย `numeric` แทน floating point

## ความปลอดภัยและความเป็นส่วนตัว

- เปิด RLS ทุกตารางที่มีข้อมูลผู้ใช้ และเขียน policy ให้ผู้ใช้เข้าถึงได้เฉพาะแถวของตนเอง; ตรวจ ownership ใน server route ซ้ำ
- Storage bucket เป็น private ใช้ signed URL อายุสั้นเมื่อจำเป็น; path ผูกกับ user ID และตรวจสิทธิ์ก่อนอ่าน/ลบ
- เก็บ Gemini API key และ Supabase service role key เฉพาะฝั่ง server; ห้ามใช้ service role ใน browser
- จำกัดขนาด/ชนิดไฟล์ ตรวจ MIME และเนื้อหา, rate limit endpoint สแกน, ตั้ง timeout และจัดการ quota/error
- ไม่ส่งข้อมูลส่วนบุคคลเกินจำเป็นให้โมเดล; ระบุใน UI ว่าภาพถูกส่งไปประมวลผลโดยบริการ AI และกำหนดวิธีลบไฟล์/ข้อมูล
- Log เฉพาะ request ID และสถานะ หลีกเลี่ยงบันทึกรูปหรือข้อมูลการเงินลง log

## ลำดับพัฒนา

### เฟส 0 — ตั้งต้นและตัดสินใจ (ครึ่งวัน–1 วัน)
ยืนยันสกุลเงินเริ่มต้น (แนะนำ THB), timezone, หมวดมาตรฐาน, เกณฑ์ขนาดภาพ, ผู้ให้บริการ deploy และรูปแบบแจ้งเตือนในแอป

### เฟส 1 — Foundation (1–2 วัน)
ตั้ง Next.js/TypeScript/Tailwind/shadcn, environment config, Supabase client แยก browser/server, layout, navigation, validation และ migration แรก

### เฟส 2 — Auth และข้อมูลธุรกรรม (2–3 วัน)
สมัคร/เข้าสู่ระบบ, RLS, seed หมวดเริ่มต้น, CRUD ธุรกรรม, ตัวกรองเดือน/หมวด และหน้ารายการ

### เฟส 3 — Dashboard (1–2 วัน)
สรุปยอดรายเดือน, กราฟเทียบรายรับ–รายจ่าย, breakdown หมวด และ empty/loading/error states

### เฟส 4 — Budget (1–2 วัน)
ตั้ง/แก้งบรายเดือน, คำนวณยอดใช้จากรายการ expense ที่ยืนยันแล้ว และแสดงระดับ 80%/100%

### เฟส 5 — Receipt Scanner (2–4 วัน)
private storage, upload flow, server route สำหรับ Gemini, JSON schema + validation, review/edit form, ยืนยันเพื่อสร้างธุรกรรม และ retry/error handling

### เฟส 6 — เก็บงานและปล่อย MVP (1–2 วัน)
ตรวจ responsive/accessibility, ตรวจ RLS และ storage policies, เพิ่มการลบข้อมูล/ใบเสร็จ, ตั้งค่า production secrets, deploy และตรวจ flow หลักบน production

**ประมาณการรวม:** 8–14 วันทำงานสำหรับ MVP โดยสมมติว่าทำคนเดียวและไม่รวมเวลารอการตั้งค่าบัญชี/บริการภายนอก

## เกณฑ์พร้อมส่ง MVP

- ผู้ใช้สองบัญชีไม่สามารถอ่านหรือแก้ข้อมูลของกันและกันได้ รวมถึง URL หรือ storage path ที่เดาได้
- ธุรกรรมที่ยืนยันแล้วเท่านั้นที่มีผลต่อ dashboard และงบประมาณ
- ผลสแกนถูกแสดงให้ตรวจ/แก้ก่อนบันทึก; กรณี AI ล้มเหลว ผู้ใช้ยังกรอกเองได้
- ยอดคำนวณถูกต้องตามเดือนและ timezone ของโปรไฟล์; ไม่เกิดการปัดเศษผิดจาก floating point
- ใช้แอปหลักได้บนมือถือ และแสดงข้อผิดพลาดของ upload, AI, auth และ network อย่างเข้าใจได้
- ผู้ใช้ลบใบเสร็จและข้อมูลบัญชีได้ตามนโยบาย retention ที่กำหนด

## ความเสี่ยงและแนวรับมือ

- **AI อ่านยอด/วันที่ผิด:** ต้องมีหน้า review, validation และการแก้ไขด้วยมือ; เก็บ confidence เพื่อช่วยจัดลำดับการตรวจ
- **ใบเสร็จหลายรูปแบบ/ภาษา:** เริ่มรองรับภาพภาษาไทยและอังกฤษ พร้อมชุดข้อมูลทดสอบจริงที่ลบข้อมูลส่วนบุคคลแล้ว ก่อนเพิ่มชนิดเอกสาร
- **ค่าใช้จ่ายหรือ quota ของ Gemini:** จำกัดขนาดภาพและจำนวนครั้ง, ป้องกันการส่งซ้ำ, แสดง error และเพิ่ม rate limit
- **ข้อมูลรั่วจาก policy/storage:** เขียน RLS ตั้งแต่ migration แรกและตรวจ policies ทั้ง database กับ bucket ก่อน deploy
- **ความคลาดเคลื่อนของยอดตาม timezone:** เก็บ timestamp แบบมาตรฐานและกำหนดชัดว่ารายงานจัดกลุ่มตาม timezone ผู้ใช้

## คำถามที่ควรตัดสินใจก่อนเริ่มลงมือ

1. ใช้ THB และ timezone Asia/Bangkok เป็นค่าเริ่มต้นหรือไม่?
2. แจ้งเตือนใน MVP เป็นแถบ/ข้อความใน Dashboard หรือจำเป็นต้องส่งอีเมล/push?
3. ใบเสร็จต้องเก็บย้อนหลังนานเท่าใด และผู้ใช้ต้องลบรูปแยกจากธุรกรรมได้หรือไม่?
4. ต้องการรองรับหลายสกุลเงินตั้งแต่รุ่นแรกหรือเริ่มด้วยสกุลเงินเดียว?

