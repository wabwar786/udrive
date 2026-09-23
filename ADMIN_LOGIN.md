# Admin portal login — username aur password

Customer aur driver app pehle ki tarah OTP se chalti hai. **Admin portal ab
username + password se** khulta hai, kyunke WhatsApp OTP ki settings isi portal
ke andar hain — agar portal bhi OTP par hota to WA Engine kharab hone par koi
andar ja kar theek hi nahi kar sakta tha.

## Pehli dafa — pehla admin banana (Railway se)

1. Jis number ko admin banana hai, us se **ek dafa app par OTP se login** karein
   (taake us ka account ban jaye), aur us account ko portal role dein
   (SuperAdmin / Admin / Manager …).
2. Railway → **udrive-api → Variables** mein yeh 3 variables daalein:

   ```
   ADMIN_BOOTSTRAP_PHONE     = 03001234567
   ADMIN_BOOTSTRAP_USERNAME  = admin
   ADMIN_BOOTSTRAP_PASSWORD  = (kam az kam 10 characters, letters + numbers)
   ```

3. Deploy hone dein. Logs mein aaye ga:
   `Portal credentials bootstrapped for admin`.
4. Portal par us username/password se login karein.
5. **`ADMIN_BOOTSTRAP_PASSWORD` foran hata dein** (baqi do rehne dein ya woh bhi
   hata dein). Password pehle se set ho to yeh dobara kuch nahi karta, is liye
   accidentally purana password wapas nahi lagta.

Agar kabhi password bhool jayen: wahi 3 variables dobara daal kar
`ADMIN_BOOTSTRAP_FORCE=true` bhi add kar dein, deploy karein, phir teeno hata dein.

## Baqi admins ko login dena

Portal → **System settings → Portal logins** (sirf SuperAdmin ko dikhta hai):
mobile number, username aur password daal kar Save. Us account ka portal role
pehle se hona chahiye.

## Apna password badalna

Portal → **System settings → My password**. Password badalte hi aap ke tamam
devices se session khatam ho jata hai — dobara login karna hoga.

## Security

- Password PBKDF2-HMAC-SHA256 (210,000 iterations, per-password salt) se hash
  hota hai; kahin plain text mein nahi rehta.
- 5 ghalat koshishon par account **15 minute** ke liye lock ho jata hai.
- Ghalat username ya ghalat password — dono ka jawab ek hi hai, taake koi
  username guess na kar sake.
- Sirf portal role wale accounts is endpoint se login kar sakte hain; customer
  ya driver ka account yahan se andar nahi aa sakta.
- Password badalne ya reset hone par us user ke tamam refresh tokens revoke ho
  jate hain.
