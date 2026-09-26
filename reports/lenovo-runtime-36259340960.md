# Lenovo TB350FU runtime audit

- target build from device log: `TB350FU_S231044_260105_ROW`
- downloaded forensic package: `https://support.halabtech.com/index.php?a=downloads&b=file&c=download&id=1043822`
- scope: read-only identification of the classpath artifact behind the Lenovo battery NPE
- this package is **not** used as a HyperOS donor or copied into an output image

## Download-route diagnostic

- HalabTech returned an HTML/login response instead of a ZIP to an anonymous request.
- alternative public page: `https://filewale.com/files/lenovo-tab-p11-gen-2-tb350fu_user_s231044_2601050946_mp_row_filewalecomzip/45346`
```
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=1080&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=1200&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=128&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=16&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=1920&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=256&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=32&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=384&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=48&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=64&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=640&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=750&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=828&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=96&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=1080&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=1200&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=128&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=16&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=1920&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=256&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=32&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=384&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=48&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=64&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=640&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=750&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=828&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=96&amp;q=75
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1778443525060-331651893.gif\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1778443609283-671133185.svg\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1778444536629-997633836.png\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1779798451506-100990746.png
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1779798451506-100990746.png\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1779798451506-100990746.png\\\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1779798890456-115967878.png
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1779798890456-115967878.png\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1784209866013-950161766.jpg\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1788932788385-828869750.jpeg\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1790142234057-688669780.png\
https://dhbv6ec3d056z.cloudfront.net\
https://filewale.com/dashboard/downloads
https://filewale.com/dashboard/downloads\
https://filewale.com/files/lenovo-tab-p11-gen-2-tb350fu_user_s231044_2601050946_mp_row_filewalecomzip/45346
https://filewale.com/files/lenovo-tab-p11-gen-2-tb350fu_user_s231044_2601050946_mp_row_filewalecomzip/45346\
https://filewale.com/files/lenovo-tab-p11-gen-2-tb350fu_user_s231044_2601050946_mp_row_filewalecomzip/45346\\\
```

### Filewale client route hints
```
lenovo-runtime-audit/filewale-js/143-269803e287419ea1.js:["path",{d:"m9 15 3 3 3-3",key:"1npd3o"}]])},20478:(e,a,t)=>{t.d(a,{A:()=>y});let y=(0,t(57568).A)("download",[["path",{d:"M12 15V3",key:"m9g1x1"}],["path",{d:"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4",key:"ih7n3h"}],["path",{d:"m7 10 5 5 5-5",key:"brsn70"}]])},21440:(e,a,t)=>{t.d(a,{A:
lenovo-runtime-audit/filewale-js/2173-560239953b084a56.js:async()=>{let{data:e}=await a.uE.get("/settings/file-manager/public");return e?.data??e??{}},requestDownload:async(e,t)=>{let r=n(e),l=t?.deviceFingerprint?.trim(),{data:i}=await a.uE.get(`/file-manager/public/file-items/${r}/request-download`,{params:t?.orderId?{orderId:t.orderId}:void 
lenovo-runtime-audit/filewale-js/234-183657638d06936a.js: o,i,s,a,u,l,f=eX(e),c=f.data,h=es.from(f.headers).normalize(),{responseType:p,onUploadProgress:d,onDownloadProgress:y}=f;function g(){a&&a(),u&&u(),f.cancelToken&&f.cancelToken.unsubscribe(o),f.signal&&f.signal.removeEventListener("abort",o)}let m=new XMLHttpRequest;function b(){if(!m)r
lenovo-runtime-audit/filewale-js/234-183657638d06936a.js:/s:void 0,bytes:u,rate:l||void 0,estimated:l&&s?(s-a)/l:void 0,event:r,lengthComputable:null!=s,[t?"download":"upload"]:!0})},r)},eq=(e,t)=>{let r=null!=e;return[n=>t[0]({lengthComputable:r,total:e,loaded:n}),t[1]]},ez=e=>(...t)=>Z.asap(()=>e(...t)),eH=ex.hasStandardBrowserEnv?(i=new URL
lenovo-runtime-audit/filewale-js/234-183657638d06936a.js:rn null==r?g(t):r};return async e=>{let t,{url:r,method:n,data:u,signal:f,cancelToken:c,timeout:h,onDownloadProgress:g,onUploadProgress:b,responseType:w,headers:E,withCredentials:v="same-origin",fetchOptions:O,maxContentLength:R,maxBodyLength:A}=eX(e),S=Z.isNumber(R)&&R>-1,T=Z.isNumber(A
lenovo-runtime-audit/filewale-js/234-183657638d06936a.js:s:s,withXSRFToken:s,adapter:s,responseType:s,xsrfCookieName:s,xsrfHeaderName:s,onUploadProgress:s,onDownloadProgress:s,decompress:s,maxContentLength:s,maxBodyLength:s,beforeRedirect:s,transport:s,httpAgent:s,httpsAgent:s,cancelToken:s,socketPath:s,allowedSocketPaths:s,responseEncoding:s,
lenovo-runtime-audit/filewale-js/2426-595d38cdf69e2f26.js:"datetime","decoding","default","dir","disabled","disablepictureinpicture","disableremoteplayback","download","draggable","enctype","enterkeyhint","exportparts","face","for","headers","height","hidden","high","href","hreflang","id","inert","inputmode","integrity","ismap","kind","label","
lenovo-runtime-audit/filewale-js/3600.7852c9e557662d8e.js:"},{label:"Courses",href:"/courses"},{label:"Physical Products",href:"/shop?type=physical"},{label:"Download Packages",href:"/subscriptions"},{label:"Request Item",href:"/request-item"}],company:[{label:"About Us",href:"/about"},{label:"Our Team",href:"/team"},{label:"Resellers",href:"/p
lenovo-runtime-audit/filewale-js/3600.7852c9e557662d8e.js:d/orders"},{label:"Wishlist",href:"/wishlist"},{label:"Wallet",href:"/dashboard/wallet"},{label:"My Downloads",href:"/dashboard/downloads"}]},n={shop:[{label:"Shop All",href:"/shop"}],company:[{label:"About Us",href:"/about"},{label:"Our Team",href:"/team"},{label:"Resellers",href:"/part
lenovo-runtime-audit/filewale-js/435-5e51a78add61bcaa.js:9 15 3 3 3-3",key:"1npd3o"}]])},20478:(e,t,r)=>{"use strict";r.d(t,{A:()=>n});let n=(0,r(57568).A)("download",[["path",{d:"M12 15V3",key:"m9g1x1"}],["path",{d:"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4",key:"ih7n3h"}],["path",{d:"m7 10 5 5 5-5",key:"brsn70"}]])},21440:(e,t,r)=>{"use stri
lenovo-runtime-audit/filewale-js/435-5e51a78add61bcaa.js:?void 0:r.href;if(n){let t=window.location.href,a=""!==r.target,s=["tel:","mailto:","sms:","blob:","download:"].some(e=>n.startsWith(e));if(!_(window.location.href,r.href))return;let i=l(t,n)||w(window.location.href,r.href);if(!f&&i)return;n===t||a||s||i||e.ctrlKey||e.metaKey||e.shiftKey
lenovo-runtime-audit/filewale-js/4731.79ed0516222baf80.js:d text-neutral-500 dark:text-neutral-400",children:w||(a?(0,o.iZ)(l):`${l||"Our store"} — products, downloads, and services in one place.`)}),(0,r.jsxs)("div",{children:[(0,r.jsx)("p",{className:"text-xs font-semibold uppercase tracking-[0.14em] text-neutral-500 dark:text-neutral-400",ch
lenovo-runtime-audit/filewale-js/4870-8156187bf527bbce.js:2 2.122 0 0 0 1.597-1.16z",key:"r04s7s"}]])},20478:(e,t,n)=>{n.d(t,{A:()=>r});let r=(0,n(57568).A)("download",[["path",{d:"M12 15V3",key:"m9g1x1"}],["path",{d:"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4",key:"ih7n3h"}],["path",{d:"m7 10 5 5 5-5",key:"brsn70"}]])},34969:(e,t,n)=>{n.d(t,{A:
lenovo-runtime-audit/filewale-js/7257-a31e7d9dbb3e07b5.js:ps")?n.replace(/^https/,"wss"):n.replace(/^http/,"ws"));let i={nodeEnv:"production".trim(),apiUrl:"/api/v1",serverApiUrl:"/api/v1",wsUrl:a,ga4Id:void 0,adminUrl:n?`${n}/admin`:void 0,siteUrl:n},o=i},25781:(e,t,r)=>{r.d(t,{F:()=>n});function n(e,t=30){if(!e?.trim())return!0;try{let r=
lenovo-runtime-audit/filewale-js/7437.2ebcd5405ca0deb8.js:"},{label:"Courses",href:"/courses"},{label:"Physical Products",href:"/shop?type=physical"},{label:"Download Packages",href:"/subscriptions"},{label:"Request Item",href:"/request-item"}],company:[{label:"About Us",href:"/about"},{label:"Our Team",href:"/team"},{label:"Resellers",href:"/p
lenovo-runtime-audit/filewale-js/7437.2ebcd5405ca0deb8.js:d/orders"},{label:"Wishlist",href:"/wishlist"},{label:"Wallet",href:"/dashboard/wallet"},{label:"My Downloads",href:"/dashboard/downloads"}]},o={shop:[{label:"Shop All",href:"/shop"}],company:[{label:"About Us",href:"/about"},{label:"Our Team",href:"/team"},{label:"Resellers",href:"/part
lenovo-runtime-audit/filewale-js/7437.2ebcd5405ca0deb8.js:ions","/recent-files","/paid-files","/free-files","/folders","/reseller","/distributor","/dashboard/downloads"];function n(){return!1}function o(e){let r=e?.storefront?.searchPlaceholder?.trim();return r||"Search wall lights, lamps, and d\xe9cor…"}function c(e){let r=e.trim()||"Our store
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js: flex-1 break-words pt-0.5",children:e.usage.dailyFiles.unlimited?`${e.usage.dailyFiles.used} files downloaded`:`${e.usage.dailyFiles.used} / ${e.usage.dailyFiles.limit} files`})]}),(0,r.jsxs)("div",{className:"flex min-w-0 flex-1 items-start gap-2 text-sky-800 dark:text-sky-300",childre
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:"daily")&&t.includes("limit")||t.includes("total")&&t.includes("limit")&&t.includes("plan")?{title:"Download limit reached",message:r.message||"You have reached a download limit on your current plan.",action:"buy"}:"PREMIUM_OR_PURCHASE_REQUIRED"===s||t.includes("premium download package"
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:)?{title:"Premium package required",message:r.message||"Download this file with an active premium package, or buy it separately.",action:"buy"}:x(r.status,r.data)?{title:"Purchase required",message:r.message||"This file is not included in your 
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:,j=(0,s.useCallback)(async()=>{let e=a.pendingDeviceAuth;if(e){m(t=>({...t,pendingDeviceAuth:null,isDownloading:!0,downloadingFileItemId:e.fileItemId}));try{let e=await p(),a=await u.$.getMySubscription();if(!a?.id)throw Error("No active subscription to authorize this device against. Cho
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:,n=u.response?.status;if(a?.quiet)throw m(e=>({...e,authorizeEmailUpdating:!1,isDownloading:!1,downloadingFileItemId:null})),Error(H(i)||"Failed to update authorize email.");if(function(e,t){if(403!==e||!t)return!1;if("DEVICE_NOT_TRUSTED"===h(t))return!0;let a=g(t).toLowerCase();ret
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:,onClose:f}),(0,r.jsx)(A,{open:!!a.pendingDeviceAuth,onClose:b,onAuthorize:j}),(0,r.jsx)(B,{ready:a.downloadReady,onClose:w,onChangeAuthorizeEmail:k,authorizeEmailUpdating:a.authorizeEmailUpdating})]})}function V(){let e=(0,s.useContext)(Y);if(!e)throw Error("useFileDownloadContext must 
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:-800/90 dark:text-amber-300/90",children:"Use this password to open the ZIP or protected file after download."})]}):null,e.usage&&!I&&(0,r.jsxs)("div",{className:"min-w-0 overflow-hidden rounded-lg border border-sky-200 bg-sky-50 px-3 py-2.5 space-y-2 dark:border-sky-800/50 dark:bg-sky-9
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:-semibold leading-snug text-foreground dark:text-white sm:text-lg",children:k?"\uD83D\uDCE5 Already Downloaded":"⬇️ Download Ready"}),(0,r.jsx)("p",{className:"mt-1 text-sm leading-relaxed text-neutral-500 break-words dark:text-neutral-400",children:k?"Your link is still valid. Downloadi
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:.e,isDownloading:!1,downloadingFileItemId:null,authorizeEmailUpdating:!1})),window.location.href=`/checkout?fileItemId=${e.fileItemId}`;return}if(401===n){m(e=>({...e,isDownloading:!1,downloadingFileItemId:nu
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:Case()}:{}}),n=l.data,o=n.url?.trim()||(n.token?`/api/v1/files/download/${n.token}`:""),d="string"==typeof n.password&&n.password.trim()?n.password.trim():void 0;return{url:o,token:n.token,expiresAt:n.expiresAt?new Date(n.expiresAt):null,reused:n.reus
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:Downloads are paused until it is reactivated or you switch to another active package.",action:"buy"}:"PACKAGE_DEACTIVATED"===s||t.includes("package has been deactivated")?{title:"Package d
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:Id;if(!0!==g)for(let e of(t.setQueryData((0,K.v3)(s),e=>e&&"object"==typeof e?{...e,downloadCount:(e.downloadCount||0)+1,viewCount:(e.viewCount||0)+1}:e),t.invalidateQueries({queryKey:(0,K.v3)(s)}),W))t.invalidateQueries({queryKey:[e]})}catch(u){let t,s,i=u.response?.data
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:a.includes("device")&&(a.includes("authoriz")||a.includes("trust"))}(n,i))return void m(t=>({...t,isDownloading:!1,downloadingFileItemId:null,authorizeEmailUpdating:!1,pendingDeviceAuth:e,error:null}));let o=H(i)||u?.message||"Failed to start download.";if(x(n,i)&&e.fileItemId){m(e=>({..
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:ail:h??e.authorizeEmail},downloadReady:{url:l??"",token:n,title:e.title,expiresAt:o??void 0,reused:g,sharedWithEmail:h,authorizeEmailOptions:x,password:f,usage:d}})),d&&(0,c.EQ)(t,d),(0,c.qE)(t);var r,s=e.fileItem
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:be used within FileDownloadProvider");return e}},65712:(e,t,a)=>{a.d(t,{Z:()=>l});var r=a(15283),s=a(30663);function i(e){if(e&&"object"==typeof e&&"data"in e){let t=e.data;if(null!=t)return t}return e}let l
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:dCount:t.totalFiles?.used??e.downloadCount}}function s(e,t){let a=e.getQueryData(["my-subscription"]),s=a?.id;e.setQueryData(["my-subscription"],e=>e?r(e,t):e),e.setQueriesData({queryKey:["my-subscriptions"]},e=>e?.le
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:e email limit",message:r.message||"You have reached the maximum number of authorize emails for this download.",action:"none"}:"AUTHORIZE_EMAIL_FIELD_DISABLED"===s||t.includes("changing the authorize email is disabled")?{title:"Authorize email unavailable",message:r.message||"Changing the
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:e:"text-lg font-semibold leading-snug text-foreground sm:text-[22px]",children:"Check device before download"}),(0,r.jsx)("p",{className:"mt-1 text-xs leading-relaxed text-neutral-500 break-words",children:"Verify this browser and existing package devices before authorizing. After one au
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:eactivated",message:r.message||"Your current download package has been deactivated. Buy a new plan or switch to another active package to download files.",action:"buy"}:"PACKAGE_PENDING"===s||t.includes("package is not active yet")?{
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:es("no active download package")||t.includes("download package is required")||t.includes("do not have an active download package")||t.includes("no active")&&t.includes("package")?{title:"No active package",message:r.message||"You do n
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:expiresAt:o,usage:d,reused:g,sharedWithEmail:h,authorizeEmailOptions:x,password:f}=await u.$.requestDownload(e.fileId??void 0,e.fileItemId,i,e.orderId,e.authorizeEmail);m(t=>({...t,isDownloading:!1,downloadingFileItemId:null,authorizeEmailUpdating:!1,lastDownloadPayload:{...e,authorizeEm
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:g-primary/10 dark:bg-primary/20",o="text-primary"},49761:(e,t,a)=>{function r(e,t){return{...e,dailyDownloadCount:t.dailyFiles?.used??e.dailyDownloadCount,dailyBandwidthUsedGB:t.dailyBandwidth?.used??e.dailyBandwidthUsedGB,bandwidthUsedGB:t.totalBandwidth?.used??e.bandwidthUsedGB,downloa
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:g. Please try again."}function J({children:e}){let t=(0,i.useQueryClient)(),[a,m]=(0,s.useState)({isDownloading:!1,downloadingFileItemId:null,authorizeEmailUpdating:!1,error:null,downloadReady:null,pendingDeviceAuth:null,lastDownloadPayload:null}),f=(0,s.useCallback)(()=>m(e=>({...e,erro
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:ge||"Please sign in to download this file.",action:"login"}:"PACKAGE_SUSPENDED"===s||t.includes("package is suspended")?{title:"Package suspended",message:r.message||"Your current download package is suspended. 
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:h(a){let t=a.response?.data?.error?.message??a.message??"Failed to authorize device.";m(a=>({...a,isDownloading:!1,downloadingFileItemId:null,pendingDeviceAuth:e,error:{title:"Authorization Failed",message:t}}));return}await v(e)}},[a.pendingDeviceAuth,v,t]),E=(0,s.useCallback)(e=>a.down
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:ice:async(e,t)=>{let{data:a}=await r.uE.post(`/subscriptions/${e}/devices`,t);return a.data},requestDownload:async(e,t,a,s,i)=>{let{data:l}=await r.uE.post("/subscriptions/request-download",{fileId:e,fileItemId:t,deviceFingerprint:a,orderId:s,...i?.trim()?{authorizeEmail:i.trim().toLower
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:idth quota.":"Your file is prepared behind a protected ShadowGrow link. Click below to continue the download."}),O?(0,r.jsx)("div",{className:"mt-2 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2.5 text-left text-xs leading-relaxed text-emerald-800 dark:border-emerald-800/60
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:ile.",action:"login"}})),"blocked")}(m))try{m(t=>({...t,isDownloading:!a?.quiet,downloadingFileItemId:a?.quiet?t.downloadingFileItemId:e.fileItemId,authorizeEmailUpdating:a?.quiet===!0,error:null,downloadReady:a?.quiet?t.downloadReady:null}));let i=await p(),{url:l,to
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:loadingFileItemId===e,[a.downloadingFileItemId]),N={...a,downloadFile:v,isDownloadingFile:E,clearError:f,clearReady:w,clearPendingDeviceAuth:b,authorizeDeviceAndDownload:j,changeAuthorizeEmail:k};return(0,r.jsxs)(Y.Provider,{value:N,children:[e,(0,r.jsx)(Z,{erro
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:md px-5 text-sm font-medium sm:h-9 sm:w-auto"),(i||l)&&"pointer-events-none opacity-60"),children:["Download Now",(0,r.jsx)(P.A,{className:"ml-1.5 h-3.5 w-3.5 shrink-0"})]}):(0,r.jsx)(f.Rx,{disabled:!0,className:(0,j.aw)("m-0 h-10 w-full rounded-md px-5 text-sm font-medium sm:h-9 sm:w-au
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:n null;let b=function(e){let t=e.url?.trim();if(t)return q(t);let a=e.token?.trim();if(a)return q(`/api/v1/files/download/${a.trim()}`);return""}({url:e.url,token:e.token}),y=void 0!==e.expiresAt&&null!==e.expiresAt,k=!0===e.reused,I=e.usage&&0===e.usage.dailyFiles.used&&0===e.usage.
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:n.getState();return t?.trim()?(0,n.F)(t)?(e(e=>({...e,isDownloading:!1,downloadingFileItemId:null})),(0,l.uS)(),"blocked"):"ok":(e(e=>({...e,isDownloading:!1,downloadingFileItemId:null,error:{title:"Sign in required",message:"Please sign in to download this f
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:ng-relaxed text-neutral-500 break-words",children:"Authorizing will remember this device for future downloads on this plan."})]})})]}),(0,r.jsxs)(f.ck,{className:"mt-6 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-end",children:[(0,r.jsx)(f.Rx,{onClick:a,className:(0,j.aw)("
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:ot have an active download package. Please buy a plan to download this file.",action:"buy"}:t.includes("subscription has expired")||t.includes("expired")&&t.includes("subscription")?{title:"Package expired",message:r.message||"Your download pack
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:plan. Purchase it separately to download.",action:"none"}:{title:r.fallbackTitle??"Download failed",message:r.message||"Something went wrong. Please try again.",action:"none"});m(e=>({...e,isDownloading:!1,downloadingFileItemId:null,authorizeEmailUpdating:!1,error:{title
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:px] text-emerald-700/90 dark:text-emerald-400/90",children:"This only changes Drive access for this download — not your profile email."}),(0,r.jsx)(C.p,{type:"email",autoComplete:"email",value:o,disabled:i,onChange:e=>{d(e.target.value),u&&c(null)},placeholder:"name@gmail.com",className:
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:r:null})),[]),w=(0,s.useCallback)(()=>m(e=>({...e,downloadReady:null,authorizeEmailUpdating:!1})),[]),b=(0,s.useCallback)(()=>m(e=>({...e,pendingDeviceAuth:null})),[]),y=(0,s.useCallback)(async(e,a)=>{if("ok"===function(e){let{token:t}=o.
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:thorize, the same network can download from another browser without a second prompt."})]})]}),(0,r.jsx)(f.$v,{asChild:!0,children:(0,r.jsxs)("div",{className:"min-w-0 space-y-4 text-sm text-neutral-600",children:[(0,r.
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:title:"Package pending",message:r.message||"Your download package is not active yet. Complete payment or wait for activation before downloading files.",action:"buy"}:"NO_ACTIVE_PACKAGE"===s||t.includes("no active subscription")||t.includ
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:to"),children:"Download unavailable"}),(0,r.jsx)(f.Zr,{onClick:t,disabled:i,className:(0,E.cn)("m-0 h-10 w-full rounded-md border border-neutral-300 bg-neutral-100 text-sm font-medium text-neutral-800","
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:uthorizeEmailUpdating:!1})),(0,l.uS)();return}let d=(t=(r={message:o,status:n,data:i,fallbackTitle:"Download failed"}).message.toLowerCase(),s=h(r.data),401===r.status||t.includes("please login")||t.includes("sign in")||t.includes("unauthorized")?{title:"Sign in required",message:r.messa
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:}))}},[t]),v=(0,s.useCallback)(async e=>{await y(e)},[y]),k=(0,s.useCallback)(async e=>{let t=a.lastDownloadPayload,r=a.downloadReady;if(!t||!r)throw Error("No active download to update.");await y({...t,authorizeEmail:e.trim().toLowerCase()},{quiet:!0})},[y,a.lastDownloadPayload,a.downlo
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js:}),e.invalidateQueries({queryKey:["my-subscriptions"]})}function l(e,t){return t&&t.id===e.id?{...e,downloadCount:t.downloadCount,bandwidthUsedGB:t.bandwidthUsedGB,dailyDownloadCount:t.dailyDownloadCount,dailyBandwidthUsedGB:t.dailyBandwidthUsedGB,devices:t.devices??e.devices}:e}a.d(t,{E
lenovo-runtime-audit/filewale-js/8239-f7803b86fa757434.js:"},{label:"Courses",href:"/courses"},{label:"Physical Products",href:"/shop?type=physical"},{label:"Download Packages",href:"/subscriptions"},{label:"Request Item",href:"/request-item"}],company:[{label:"About Us",href:"/about"},{label:"Our Team",href:"/team"},{label:"Resellers",href:"/p
lenovo-runtime-audit/filewale-js/8239-f7803b86fa757434.js:async()=>{let{data:e}=await l.uE.get("/settings/file-manager/public");return e?.data??e??{}},requestDownload:async(e,r)=>{let t=i(e),a=r?.deviceFingerprint?.trim(),{data:s}=await l.uE.get(`/file-manager/public/file-items/${t}/request-download`,{params:r?.orderId?{orderId:r.orderId}:void 
lenovo-runtime-audit/filewale-js/8239-f7803b86fa757434.js:d/orders"},{label:"Wishlist",href:"/wishlist"},{label:"Wallet",href:"/dashboard/wallet"},{label:"My Downloads",href:"/dashboard/downloads"}]},o={shop:[{label:"Shop All",href:"/shop"}],company:[{label:"About Us",href:"/about"},{label:"Our Team",href:"/team"},{label:"Resellers",href:"/part
lenovo-runtime-audit/filewale-js/8239-f7803b86fa757434.js:ions","/recent-files","/paid-files","/free-files","/folders","/reseller","/distributor","/dashboard/downloads"];function n(){return!1}function o(e){let r=e?.storefront?.searchPlaceholder?.trim();return r||"Search wall lights, lamps, and d\xe9cor…"}function u(e){let r=e.trim()||"Our store
lenovo-runtime-audit/filewale-js/9408.71638c5115644c3e.js: r=new Date(e.endDate).getTime();return!!Number.isFinite(r)&&r>Date.now()}function n(e,r){let t="maxDownloads"===r?e.planMaxDownloads:"maxBandwidthGB"===r?e.planMaxBandwidthGB:"maxDevices"===r?e.planMaxDevices:"dailyDownloadLimit"===r?e.planDailyDownloadLimit:e.planDailyBandwidthLimitGB,
lenovo-runtime-audit/filewale-js/9408.71638c5115644c3e.js:",{className:"font-medium tabular-nums text-neutral-800 dark:text-neutral-200",children:0===n?`${t} downloaded`:`${t} / ${n}`})]}),(0,a.jsx)("div",{className:"h-1.5 overflow-hidden rounded-full bg-green-500/20 dark:bg-green-500/25",children:(0,a.jsx)("div",{className:"h-full rounded-full
lenovo-runtime-audit/filewale-js/9408.71638c5115644c3e.js:cription"],queryFn:$.$.getMySubscription,enabled:Q,retry:1,staleTime:0}),e$=(0,q.s)(eT),eq=eT?.dailyDownloadCount??0,eP=e$&&eT?(0,q.h)(eT,"dailyDownloadLimit"):0,eG=Number(eT?.dailyBandwidthUsedGB??0),eW=e$&&eT?Number((0,q.h)(eT,"dailyBandwidthLimitGB")):0,eO=Number(eT?.bandwidthUsedGB??
lenovo-runtime-audit/filewale-js/9408.71638c5115644c3e.js:f:"/dashboard/subscriptions",surfaces:["sidebar","dropdown"],sidebarIcon:s.A,dropdownIcon:i.A},{id:"downloads",label:"Downloads",href:"/dashboard/downloads",surfaces:["sidebar","dropdown"],sidebarIcon:o.A,dropdownIcon:d.A},{id:"wallet",label:"Wallet",href:"/dashboard/wallet",surfaces:["s
lenovo-runtime-audit/filewale-js/9568-ddae15ca3d8c08b4.js:rlKey||e.shiftKey||e.altKey||e.nativeEvent&&2===e.nativeEvent.which)||e.currentTarget.hasAttribute("download"))return;if(!(0,y.isLocalURL)(t)){o&&(e.preventDefault(),location.replace(t));return}if(e.preventDefault(),a){let e=!1;if(a({preventDefault:()=>{e=!0}}),e)return}let{dispatchNavig
lenovo-runtime-audit/filewale-js/9992-f8ee6e4afbf56b4b.js:ar-nums",children:[(0,a.jsx)(p.A,{className:"h-3.5 w-3.5 shrink-0 opacity-70","aria-hidden":!0}),(e.downloadCount??0).toLocaleString()," downloads"]}),null!=t&&(0,a.jsxs)("span",{className:"inline-flex items-center gap-1 tabular-nums",children:[(0,a.jsx)(h.A,{className:"h-3.5 w-3.5 shrin
lenovo-runtime-audit/filewale-js/c7879cf7-0d16fce1674078f9.js:n"!=typeof r&&"symbol"!=typeof r?e.setAttribute(t,""):e.removeAttribute(t);break;case"capture":case"download":!0===r?e.setAttribute(t,""):!1!==r&&null!=r&&"function"!=typeof r&&"symbol"!=typeof r?e.setAttribute(t,r):e.removeAttribute(t);break;case"cols":case"rows":case"size":case"span":n
lenovo-runtime-audit/filewale-js/layout-1c2df849d9a23b1c.js:async()=>{let{data:e}=await n.uE.get("/settings/file-manager/public");return e?.data??e??{}},requestDownload:async(e,t)=>{let r=i(e),a=t?.deviceFingerprint?.trim(),{data:s}=await n.uE.get(`/file-manager/public/file-items/${r}/request-download`,{params:t?.orderId?{orderId:t.orderId}:void 
lenovo-runtime-audit/filewale-js/page-610d8524cc3105eb.js:?(0,s.jsxs)(U.Jr,{payload:eg,className:(0,M.aw)(en),children:[(0,s.jsx)(h.A,{className:"h-4 w-4"}),"Download File"]}):eg?(0,s.jsxs)(U.Jr,{payload:eg,className:(0,M.xK)(en),children:[(0,s.jsx)(h.A,{className:"h-4 w-4"}),"Download Free"]}):null,(0,s.jsx)(B,{url:`/files/${e}/${t}`,title:eh?
lenovo-runtime-audit/filewale-js/page-610d8524cc3105eb.js:[(0,s.jsxs)(U.Jr,{payload:eg,className:(0,M.aw)(en),children:[(0,s.jsx)(h.A,{className:"h-4 w-4"}),"Download File"]}),(0,s.jsxs)(U.ZJ,{fileItemId:eh.id,className:(0,M.zE)(en),children:[(0,s.jsx)(p.A,{className:"h-4 w-4 shrink-0","aria-hidden":!0}),"Buy Now"," ",null!=eh.price&&Number(eh.
lenovo-runtime-audit/filewale-js/page-610d8524cc3105eb.js:ext-sm leading-relaxed text-emerald-800/90 dark:text-emerald-300/90",children:"This file is safe to download. Scanned by our security systems."})]})]})}),(0,s.jsxs)("div",{className:"rounded-2xl bg-card p-5 dark:bg-neutral-900",children:[(0,s.jsxs)("div",{className:"flex items-start gap-
lenovo-runtime-audit/filewale-js/page-610d8524cc3105eb.js:leView(H).then(e=>{W.setQueryData((0,ea.v3)(t),t=>t&&"object"==typeof t?{...t,viewCount:e.viewCount,downloadCount:e.downloadCount}:t)}).catch(()=>{}))},[t,W]),(0,a.useEffect)(()=>{eu(!1)},[eh?.id]);let eg=eh?{fileItemId:String(eh.id),title:eh.title,isForSale:eh.isForSale,status:eh.status
lenovo-runtime-audit/filewale-js/page-610d8524cc3105eb.js:r(99568),n=r.n(a),l=r(93292),i=r(57445),d=r(990);function o({payload:e,className:t,children:r}){let{downloadFile:a,isDownloadingFile:n}=(0,i.v)(),d=n(e.fileItemId);return(0,s.jsxs)("button",{type:"button",disabled:d,className:t,onClick:t=>{t.preventDefault(),t.stopPropagation(),a(e)},chi
lenovo-runtime-audit/filewale-js/page-610d8524cc3105eb.js:ral-500",children:[(0,s.jsx)(h.A,{className:"h-4 w-4 shrink-0 text-neutral-400","aria-hidden":!0}),"Downloads"]}),(0,s.jsx)("span",{className:"shrink-0 text-sm font-semibold tabular-nums text-foreground dark:text-neutral-100",children:eh.downloadCount||0})]}),(0,s.jsxs)("div",{className:
```

## Audit failure diagnostic

- failed command: `false`
- exit code: `1`

```
lenovo-runtime-audit/download.stderr 555 B
lenovo-runtime-audit/filewale-js.stderr 0 B
lenovo-runtime-audit/filewale-js/143-269803e287419ea1.js 10696 B
lenovo-runtime-audit/filewale-js/1846-3082dbb0a9f21c1d.js 8125 B
lenovo-runtime-audit/filewale-js/2090.798dfa613616a6b2.js 13497 B
lenovo-runtime-audit/filewale-js/2173-560239953b084a56.js 15492 B
lenovo-runtime-audit/filewale-js/234-183657638d06936a.js 65595 B
lenovo-runtime-audit/filewale-js/2426-595d38cdf69e2f26.js 27298 B
lenovo-runtime-audit/filewale-js/2721-009032ac553bde1d.js 10500 B
lenovo-runtime-audit/filewale-js/3356-3d17971d47f4a095.js 25806 B
lenovo-runtime-audit/filewale-js/3600.7852c9e557662d8e.js 8523 B
lenovo-runtime-audit/filewale-js/3966-89a8b94af787b5af.js 8766 B
lenovo-runtime-audit/filewale-js/4241-764b6ce057fb9c17.js 23369 B
lenovo-runtime-audit/filewale-js/4327-115b4e4cf5dfd289.js 25290 B
lenovo-runtime-audit/filewale-js/435-5e51a78add61bcaa.js 32398 B
lenovo-runtime-audit/filewale-js/4731.79ed0516222baf80.js 18256 B
lenovo-runtime-audit/filewale-js/4870-8156187bf527bbce.js 41768 B
lenovo-runtime-audit/filewale-js/5078-b232f286671f926c.js 8165 B
lenovo-runtime-audit/filewale-js/5158-645169a5486234db.js 222347 B
lenovo-runtime-audit/filewale-js/5263-976ae1a82fa29b48.js 8665 B
lenovo-runtime-audit/filewale-js/5751-e32f5e4b6bce95c6.js 23898 B
lenovo-runtime-audit/filewale-js/5790-1172f2514e8feb97.js 18855 B
lenovo-runtime-audit/filewale-js/6525-f5c3850d382a78d3.js 33594 B
lenovo-runtime-audit/filewale-js/6618-642d202d30ebf568.js 5994 B
lenovo-runtime-audit/filewale-js/6848-23c90aad11ab291c.js 7956 B
lenovo-runtime-audit/filewale-js/7257-a31e7d9dbb3e07b5.js 11711 B
lenovo-runtime-audit/filewale-js/7437.2ebcd5405ca0deb8.js 12229 B
lenovo-runtime-audit/filewale-js/7445-462444c0fb04544c.js 42706 B
lenovo-runtime-audit/filewale-js/7615-c0fa7f5b2ea33b10.js 16327 B
lenovo-runtime-audit/filewale-js/7736-d24062201471d83b.js 24096 B
lenovo-runtime-audit/filewale-js/8137-1da3465105990475.js 14057 B
lenovo-runtime-audit/filewale-js/8239-f7803b86fa757434.js 10491 B
lenovo-runtime-audit/filewale-js/8618-efdceacee635e150.js 9245 B
lenovo-runtime-audit/filewale-js/934-50f144b66cb2308f.js 26597 B
lenovo-runtime-audit/filewale-js/9408.71638c5115644c3e.js 57477 B
lenovo-runtime-audit/filewale-js/9568-ddae15ca3d8c08b4.js 8730 B
lenovo-runtime-audit/filewale-js/968-aac88ca1b0886ecb.js 11982 B
lenovo-runtime-audit/filewale-js/9992-f8ee6e4afbf56b4b.js 26634 B
lenovo-runtime-audit/filewale-js/c7879cf7-0d16fce1674078f9.js 199869 B
lenovo-runtime-audit/filewale-js/global-error-62d74a587fa4d24e.js 808 B
lenovo-runtime-audit/filewale-js/layout-1c2df849d9a23b1c.js 31651 B
lenovo-runtime-audit/filewale-js/main-app-03f098962b3ca593.js 482 B
lenovo-runtime-audit/filewale-js/page-1c97e8048edceafe.js 1285 B
lenovo-runtime-audit/filewale-js/page-610d8524cc3105eb.js 35473 B
lenovo-runtime-audit/filewale-js/polyfills-42372ed130431b0a.js 112594 B
lenovo-runtime-audit/filewale-js/webpack-a06e4ec0785f2d27.js 5516 B
lenovo-runtime-audit/filewale-page.html 139190 B
lenovo-runtime-audit/filewale.stderr 1739 B
lenovo-runtime-audit/halab-response.html 98747 B
```

### download.stderr (tail)
```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100 43397    0 43397    0     0  33911      0 --:--:--  0:00:01 --:--:-- 33911100 98747    0 98747    0     0  68102      0 --:--:--  0:00:01 --:--:--  317k
```

### filewale.stderr (tail)
```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:01 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:02 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:03 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:04 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:05 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:06 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:07 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:08 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:09 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:10 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:11 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:12 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:13 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:14 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:15 --:--:--     0100 21877    0 21877    0     0   1342      0 --:--:--  0:00:16 --:--:--  4374100 78497    0 78497    0     0   4535      0 --:--:--  0:00:17 --:--:-- 15671100 91166    0 91166    0     0   5009      0 --:--:--  0:00:18 --:--:-- 18612100  135k    0  135k    0     0   7648      0 --:--:--  0:00:18 --:--:-- 35708
```
