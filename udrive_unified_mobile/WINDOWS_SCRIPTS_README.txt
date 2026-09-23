Windows scripts — pehle rename karein
=====================================

Is package mein teen helper scripts .txt extension ke saath hain, taake
Windows Defender download ke waqt archive ko block na kare:

  create_upload_key.bat.txt    ->  create_upload_key.bat
  build_play_bundle.bat.txt    ->  build_play_bundle.bat
  build_apk_windows.bat.txt    ->  build_apk_windows.bat

Extract karne ke baad in teenon ka ".txt" hissa hata dein (File Explorer mein
View -> File name extensions on karein, phir rename karein). Ya PowerShell se
isi folder mein:

  Get-ChildItem *.bat.txt | Rename-Item -NewName { $_.Name -replace '\.txt$','' }

Yeh saadi text files hain — khol kar khud parh sakte hain. Koi .exe, .dll ya
binary is package mein nahi hai.

Script ke baghair upload key banani ho to (isi folder mein, ek line):

  "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore "android\app\upload-keystore.jks" -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload -dname "CN=UDrive, O=Tech Geni Ltd., L=Muzaffarabad, C=PK"

Phir android\key.properties banayein:

  storePassword=AAP_KA_PASSWORD
  keyPassword=AAP_KA_PASSWORD
  keyAlias=upload
  storeFile=upload-keystore.jks
