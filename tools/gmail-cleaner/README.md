# Gmail Cleaner – ניקוי וסיווג Gmail

כלי שורת פקודה שרץ **על המחשב שלך**, מסווג את המיילים לקטגוריות ומאפשר לנקות אותם בבטחה.

**קטגוריות:** משפחה · חברים · קבלות · כספים · נסיעות · רשתות חברתיות · פרסומות · ניוזלטרים · התראות · אנשים אחרים · אחר

## בטיחות

- **מצב ניסיון כברירת מחדל.** שום דבר לא משתנה בלי `--apply`, וגם אז תתבקש להקליד `yes`.
- **אין מחיקה לצמיתות.** ההרשאה (`gmail.modify`) לא מאפשרת מחיקה. מיילים עוברים לאשפה ואפשר לשחזר אותם במשך 30 יום.
- מיילים **מסומנים בכוכב** לא נוגעים בהם אף פעם, וגם לא במיילים ש-Gmail סימן כ**חשובים** (אלא אם הוספת `--include-important`).
- הקטגוריות משפחה, חברים ואנשים אחרים **מוגנות** ודורשות `--force`.
- רק **כותרות** (שולח, נושא, תוויות, תקציר קצר) נשמרות, בקובץ מקומי `gmail_cache.db`. תוכן המיילים לא יורד ושום דבר לא נשלח לשום מקום חוץ מ-Google.

## התקנה

```bash
git clone <הריפו> gmail-cleaner && cd gmail-cleaner
python3 -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp config.example.toml config.toml                   # ערוך: משפחה, חברים, הכתובת שלך
```

נדרש Python 3.11 ומעלה.

### הגדרת גישה ל-Gmail (פעם אחת, כ-5 דקות)

1. היכנס ל-[Google Cloud Console](https://console.cloud.google.com/) וצור פרויקט חדש.
2. **APIs & Services → Library**: חפש **Gmail API** ולחץ **Enable**.
3. **Google Auth Platform → Audience** (או **OAuth consent screen**): בחר **External**, ותחת **Test users** הוסף את כתובת ה-Gmail שלך.
4. **Clients → Create client** (או **Credentials → OAuth client ID**): בחר **Desktop app**.
5. הורד את קובץ ה-JSON ושמור אותו בתיקיית הפרויקט בשם `credentials.json`.

בהרצה הראשונה ייפתח דפדפן לאישור. מכיוון שהאפליקציה שלך ולא עברה אימות של Google, תופיע אזהרה: לחץ **Advanced → Go to ... (unsafe)**. האישור נשמר ב-`token.json`. אל תשתף את הקובץ הזה ואת `credentials.json` (שניהם כבר ב-`.gitignore`).

## שימוש

```bash
# 1. סריקה וסיווג (קריאה בלבד). ברירת מחדל: שנתיים אחרונות, עד 10,000 הודעות
python -m gmail_cleaner scan
python -m gmail_cleaner scan --query "in:inbox" --max 3000

# 2. דוח: כמה הודעות ונפח בכל קטגוריה, עם דוגמאות וייצוא ל-Excel
python -m gmail_cleaner report --examples 5 --csv emails.csv

# 3. מי שולח לך הכי הרבה, כולל קישורי ביטול מנוי
python -m gmail_cleaner senders --top 30 --unsubscribe-links
python -m gmail_cleaner senders --category promotions

# 4. ניקוי: קודם מצב ניסיון, ואז אותה פקודה עם --apply
python -m gmail_cleaner clean --category promotions --older-than 30
python -m gmail_cleaner clean --category promotions --older-than 30 --apply
python -m gmail_cleaner clean --category social newsletters --older-than 90 --apply
python -m gmail_cleaner clean --sender deals@store.com spam@shop.co.il --apply
python -m gmail_cleaner clean --category notifications --action archive --apply  # הוצאה מהדואר הנכנס בלבד

# 5. תוויות ב-Gmail ("ניקוי/קבלות", "ניקוי/משפחה" וכו')
python -m gmail_cleaner label            # תצוגה מקדימה
python -m gmail_cleaner label --apply

# אחרי עריכת config.toml: סיווג מחדש בלי להוריד שוב
python -m gmail_cleaner classify
```

שמות הקטגוריות לפקודות: `family friends receipts finance travel social promotions newsletters notifications personal other`

## איך הסיווג עובד

החוקים נבדקים לפי הסדר, והחוק הראשון שמתאים קובע:

| קטגוריה | איך מזוהה |
|---|---|
| משפחה | כתובות או שם משפחה מ-`config.toml` |
| חברים | כתובות מ-`config.toml`, **או** אדם פרטי (gmail/walla וכו') ש**אתה שלחת אליו** מייל |
| קבלות | מילים בנושא: קבלה, חשבונית, אישור הזמנה, receipt, invoice… |
| כספים | דומיינים של בנקים, חברות אשראי, ביטוח, פנסיה ו-gov.il, או מילים כמו "דף חשבון" ו"חיוב" |
| נסיעות | חברות תעופה, Booking, Airbnb, "טיסה"… |
| רשתות חברתיות | Facebook, LinkedIn, Instagram וכו', או לשונית "רשתות חברתיות" של Gmail |
| פרסומות | לשונית "קידומי מכירות" של Gmail, או רשימת תפוצה עם מילים כמו מבצע, הנחה, קופון |
| ניוזלטרים | כל רשימת תפוצה אחרת (יש קישור ביטול מנוי) |
| התראות | שולחים מסוג noreply/notifications, או לשונית "עדכונים" |
| אנשים אחרים | נראה כמו אדם אמיתי שלא ברשימות שלך |

אם משהו מסווג לא נכון, הוסף דומיינים או מילים בסעיף `[rules.*]` ב-`config.toml` והרץ `classify`.

## בדיקות

```bash
pip install pytest && python -m pytest -q
```
