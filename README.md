# hayo — 待ち合わせをエンタメ化するアプリ

> NxTEND THE HACK 2026 / Team 25

「あと何分？」「今どこ？」——待ち合わせの退屈な連絡を、位置情報共有とフォトミッションでゲームに変えるiOSアプリです。

グループは使い捨てで、**全員が集合した10分後にすべてのデータ（位置情報・写真）が自動的に完全消去されます**。アカウント登録も不要で、その場限りの体験に振り切っています。

---

## 主な機能

| 機能 | 内容 |
|---|---|
| **リアルタイム位置共有** | 出発したメンバーの現在地を地図上に表示。ピンは出発時に撮った本人の丸型写真になります |
| **「はよ」催促** | 出発予定時刻を過ぎても動かないメンバーを急かせます。押された回数が `×N` で溜まり、本人に通知が飛びます |
| **フォトミッション** | 移動中にランダムなお題が突然配信されます。2分以内に写真を投稿するとクリア（青チェック） |
| **フォトチャット** | お題以外にも自由に写真を撮って共有。キャプションを重ねて投稿でき、👍と「はよ」でリアクションできます |
| **到着ランキング** | 集合時間との差（±分）とミッションクリア数で順位を表示 |
| **10分後の自動消滅** | Cloud Functions が Firestore と Storage のデータを完全削除します |

## 画面フロー

```
① スタート ──┬─ グループを作成 → ② 作成画面 → ③ 招待コード ─┐
             │                                              ├→ ④ プロフィール入力 → ⑤ ロビー
             └─ コード入力 ────────────────────────────────┘
                                                                    │
                    ┌───────────────────────────────────────────────┤
                    ↓                    ↓                          ↓
              ⑥ MAP画面          ⑦ SNAP（写真一覧）        ⑪ カメラ → ⑫ プレビュー
                    │                    │                          │
                    └────────────────────┴──────────────────────────┘
                                         ↓
                                  ⑩ 到着ランキング → 解散
```

⑤〜⑧の上部には、ミッション内容と残り時間を表示する赤い共通ヘッダー（⑨）が重なります。

---

## 技術スタック

**iOS（Swift 5 / SwiftUI, iOS 16+）**

- SwiftUI — 全画面をコードで構築
- Google Maps SDK for iOS — 地図・ピン表示・目的地選択
- CoreLocation — 位置情報取得（`distanceFilter` によるフィルタリング）
- AVFoundation — カメラ制御（BeReal風の丸型UI・倍率切替・イン/アウト切替）
- UserNotifications — アプリ内バナー＋ローカル通知

**バックエンド（Firebase）**

- Authentication（匿名認証）— アカウント登録不要
- Cloud Firestore — グループ・メンバー・写真のリアルタイム同期
- Cloud Storage — 写真の保存
- Cloud Functions（Node.js 20 / asia-northeast1）— ミッション配信・到着判定・自動削除

## ディレクトリ構成

```
.
├── GatherQuest/                    # Xcodeプロジェクト
│   ├── GatherQuest.xcodeproj
│   ├── GoogleService-Info.plist
│   └── GatherQuest/
│       ├── App/HayoApp.swift       # エントリポイント・匿名認証・画面遷移
│       ├── Models/Models.swift     # Firestoreデータモデル
│       ├── Services/               # Firestore / Storage / 位置情報 / カメラ / 通知
│       ├── Views/                  # 全12画面 + 共通コンポーネント
│       ├── Assets.xcassets         # アプリアイコン
│       └── Info.plist              # 権限設定・表示名
├── functions/index.js              # Cloud Functions
├── firestore.rules                 # Firestoreセキュリティルール
├── storage.rules                   # Storageセキュリティルール
└── firebase.json
```

---

## 設計上の判断

ハッカソンという時間制約の中で、以下の方針を採りました。

**プッシュ通知（APNs）を使わない**

証明書の設定に時間を取られるリスクを避け、Firestoreの変更監視 → アプリ内バナー＋ローカル通知という構成にしました。アプリ使用中も即座に通知が表示されるよう `UNUserNotificationCenterDelegate` で前景表示を有効化しています。体験上の差はほとんどなく、設定不備で通知が一切届かないリスクを排除できます。

**位置情報の書き込み頻度を制限**

CoreLocationの値をそのままFirestoreに流すと書き込みが爆発します。`distanceFilter = 10m`（OS側の間引き）と**15秒に1回まで**（アプリ側の間引き）の二段構えで抑制しています。加えて出発ボタンを押した瞬間だけは即時書き込みを行い、ピンがすぐ表示されるようにしています。

**リアクションは1人1回**

`likedBy` / `hayoBy` に反応済みユーザーIDを保持し、連打による水増しを防いでいます。

**Dynamic Island（Live Activities）は未実装**

コア機能の完成を優先したため、Nice-to-have として見送りました。

---

## セットアップ

### 1. Firebase

1. [Firebase Console](https://console.firebase.google.com) でプロジェクトを作成
2. iOSアプリを追加（Bundle ID を設定）→ `GoogleService-Info.plist` をダウンロードし `GatherQuest/` 直下に配置
3. Authentication → Sign-in method → **匿名** を有効化
4. Firestore Database を作成（本番モード / `asia-northeast1`）
5. Storage を開始（同ロケーション）
6. 料金プランを **Blaze** にアップグレード（Cloud Functionsのスケジュール実行に必須）

```bash
npm install -g firebase-tools
firebase login
firebase use --add                              # プロジェクトを選択
firebase deploy --only firestore:rules,storage
cd functions && npm install && cd ..
firebase deploy --only functions
```

第2世代Functionsの初回デプロイは、Eventarcの権限伝播のため失敗することがあります。5〜10分待って再実行してください。

### 2. Google Maps API キー

1. [Google Cloud Console](https://console.cloud.google.com) → APIs & Services → **Maps SDK for iOS** を有効化
2. Credentials → APIキーを作成
3. **Application restrictions を「iOS apps」にし、Bundle ID を登録**（キーの悪用防止）
4. **API restrictions を「Maps SDK for iOS」のみ**に制限
5. `App/HayoApp.swift` の `GMSServices.provideAPIKey(...)` に設定

### 3. Xcode

1. `GatherQuest/GatherQuest.xcodeproj` を開く
2. File → Add Package Dependencies で以下を追加
   - `https://github.com/firebase/firebase-ios-sdk` → FirebaseAuth / FirebaseFirestore / FirebaseStorage
   - `https://github.com/googlemaps/ios-maps-sdk` → GoogleMaps
3. Signing & Capabilities でTeamを設定
4. 実機を接続して Run

`Info.plist` には以下を設定済みです。

| Key | 用途 |
|---|---|
| `CFBundleDisplayName` | アプリ表示名（hayo） |
| `NSCameraUsageDescription` | カメラ利用の説明 |
| `NSLocationWhenInUseUsageDescription` | 位置情報利用の説明 |
| `LSApplicationQueriesSchemes` | Googleマップアプリへの遷移 |

カメラと位置情報のため**実機での動作確認を推奨**します。シミュレータの場合は Features → Location でダミー位置を設定してください。

---

## Firestore データモデル

```
groups/{groupId}
  name, destination(GeoPoint), meetTime, status(waiting|active|finished),
  inviteCode, createdAt, missionsScheduled, finishedAt

groups/{groupId}/members/{userId}
  name, expectedDepartureTime, departureTime, status(not_departed|departed|arrived),
  location(GeoPoint), iconUrl, hayoCount, arrivalTime, clearedCount

groups/{groupId}/missions/{missionId}          # Cloud Functionsのみが作成
  title, publishAt, expiresAt

groups/{groupId}/photos/{photoId}
  userId, missionId?, photoType(mission|snap|arrival), imageUrl, caption,
  timestamp, isCleared, likeCount, hayoReactionCount, likedBy[], hayoBy[]
```

## Cloud Functions

| 関数 | トリガー | 処理 |
|---|---|---|
| `onMemberUpdate` | メンバー更新時 | 最初の1人が出発したらミッション3件をランダム時刻でスケジュール。全員到着でグループを `finished` に |
| `cleanupGroups` | 毎分（スケジュール） | 集合完了から10分経過したグループのFirestore・Storageデータを完全削除 |

---

## トラブルシューティング

**地図が真っ白** — APIキーが未設定か、Maps SDK for iOS が未有効化。キー制限の変更直後は反映に数分かかります。

**ミッションが届かない** — Functionsのデプロイ状況、Blazeプラン、リージョン（`asia-northeast1`）を確認してください。

**グループが消えない** — `cleanupGroups` は毎分実行です。Cloud Schedulerの初回有効化に数分かかることがあります。

**ビルドエラー `FirebaseFirestoreSwift`** — SDK 11以降は `FirebaseFirestore` に統合済みです。SDK 10.x を使う場合のみ追加してください。

**地図にピンが出ない** — 位置情報の権限が「許可しない」になっていないか、また出発ボタンを押して `departed` 状態になっているかご確認ください。
