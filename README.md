# GatherQuest — 待ち合わせエンタメ化アプリ

期間限定の位置情報共有＆フォトミッションアプリ (iOS / SwiftUI + Firebase)。
全員集合から10分後にグループデータは自動消去されます。

## 構成

```
GatherQuest/
├── ios/GatherQuest/        # SwiftUI アプリ (Xcodeプロジェクトに追加する)
│   ├── App/                # エントリポイント・画面遷移
│   ├── Models/             # Firestoreデータモデル
│   ├── Services/           # Auth/Firestore/Storage/位置情報/カメラ/通知
│   └── Views/              # 全12画面 (テンプレート準拠)
├── functions/              # Cloud Functions (ミッション配信・自動削除)
├── firestore.rules         # Firestoreセキュリティルール
├── storage.rules           # Storageセキュリティルール
└── firebase.json
```

## 1. Firebase セットアップ（未作成の場合）

1. [Firebase Console](https://console.firebase.google.com) → 「プロジェクトを追加」→ 名前例 `gatherquest`。
2. **iOSアプリを追加**: Bundle ID を `com.yourname.GatherQuest` などに設定 → `GoogleService-Info.plist` をダウンロード。
3. **Authentication** → Sign-in method → **匿名** を有効化。
4. **Firestore Database** → データベースを作成 → 本番モード → ロケーション `asia-northeast1`。
5. **Storage** → 開始する（同ロケーション）。
6. **料金プランを Blaze にアップグレード**（Cloud Functions のスケジュール実行に必須。無料枠内でほぼ収まります）。
7. ローカルで:
   ```bash
   npm install -g firebase-tools
   firebase login
   cd GatherQuest
   firebase use --add   # 作成したプロジェクトを選択
   firebase deploy --only firestore:rules,storage
   cd functions && npm install && cd ..
   firebase deploy --only functions
   ```

## 2. Google Maps API キー

1. [Google Cloud Console](https://console.cloud.google.com)（Firebaseと同じプロジェクトでOK）→ 「APIとサービス」→ **Maps SDK for iOS** を有効化。
2. 認証情報 → APIキーを作成（iOSアプリ制限＋Bundle ID を推奨）。
3. `ios/GatherQuest/App/GatherQuestApp.swift` の `YOUR_GOOGLE_MAPS_API_KEY` を置き換え。
4. ※Maps SDK は課金有効なプロジェクトが必要です（無料クレジット枠あり）。

## 3. Xcode プロジェクト作成

1. Xcode → New Project → **iOS App** → 名前 `GatherQuest`, Interface: **SwiftUI**, Language: **Swift**。最低ターゲット **iOS 16**。
2. `ios/GatherQuest/` 内の `App/ Models/ Services/ Views/` フォルダをプロジェクトにドラッグ（"Copy items if needed" + ターゲットにチェック）。Xcodeが自動生成した `GatherQuestApp.swift`・`ContentView.swift` は削除。
3. `GoogleService-Info.plist` をプロジェクト直下に追加。
4. **Swift Package Manager** で以下を追加 (File → Add Package Dependencies):
   - `https://github.com/firebase/firebase-ios-sdk` → **FirebaseAuth / FirebaseFirestore / FirebaseFirestoreSwift(SDK10の場合) / FirebaseStorage** を選択
   - `https://github.com/googlemaps/ios-maps-sdk` → **GoogleMaps**
5. **Info.plist に以下のキーを追加**:

   | Key | 値の例 |
   |---|---|
   | `NSCameraUsageDescription` | 出発写真・ミッション写真の撮影に使用します |
   | `NSLocationWhenInUseUsageDescription` | メンバーに現在地を共有するために使用します |
   | `LSApplicationQueriesSchemes` | (Array) `comgooglemaps` |

6. Signing & Capabilities でチームを設定 → 実機で Run。
   （カメラ・位置情報のためシミュレータより実機推奨。シミュレータでは Features → Location でダミー位置を設定可能。）

## 4. 動作フロー

作成者: グループ作成 → 目的地を地図タップで選択 → 集合時間 → 招待コード発行 → 名前・出発予定時刻入力 → ロビー。
参加者: コード入力 → 名前・出発予定時刻入力 → ロビー（最大8人）。

- **はよ催促**: 出発予定時刻を過ぎた未出発メンバーに「はよ」ボタンが有効化。押すと ×N 表示＋本人に通知。
- **出発**: 丸型(BeReal風)カメラでアイコン撮影 → 位置共有開始 → 地図上に丸アイコンピン。最初の1人の出発で Cloud Functions がランダム時刻のミッション3件をスケジュール。
- **フォトミッション**: 配信から2分以内の投稿でクリア（青チェック）。2分超過でも投稿は可能（クリア判定なし）。
- **到着**: 到着ボタン → 到着写真撮影。全員到着で到着ランキング表示（集合時間との差±、ミッションクリア数バッジ）。
- **自動削除**: 全員集合10分後、Cloud Functions が Firestore + Storage のグループデータを完全削除。アプリはスタート画面へ戻ります。

## 5. リスクヘッジ方針（実装済み）

- プッシュ通知は **APNs不使用**。Firestore監視＋アプリ内バナー＋ローカル通知で実装（FCMは後日）。
- 位置情報書き込みは **distanceFilter 50m ＋ 最短15秒間隔** のダブルスロットルで Firestore Writes を抑制。
- Dynamic Island (Live Activities) は未実装（Nice-to-have）。

## 6. Firestore データモデル

```
groups/{groupId}
  name, destination(GeoPoint), meetTime, status(waiting|active|finished),
  inviteCode, createdAt, missionsScheduled, finishedAt
groups/{groupId}/members/{userId}
  name, expectedDepartureTime, status(not_departed|departed|arrived),
  location(GeoPoint), iconUrl, hayoCount, arrivalTime, clearedCount
groups/{groupId}/missions/{missionId}
  title, publishAt, expiresAt        # Cloud Functionsのみが作成
groups/{groupId}/photos/{photoId}
  userId, missionId?, photoType(mission|snap|arrival), imageUrl,
  caption, timestamp, isCleared, likeCount, hayoReactionCount
```

## トラブルシューティング

- ビルドエラー `FirebaseFirestoreSwift`: SDK 11以降は `FirebaseFirestore` に統合済み。SDK 10.x を使う場合のみ `FirebaseFirestoreSwift` を追加してください。
- 地図が真っ白: APIキー未設定か Maps SDK for iOS が未有効化。
- ミッションが届かない: Functions のデプロイと Blaze プラン、region (`asia-northeast1`) を確認。
- グループが消えない: `cleanupGroups` はスケジュール実行（毎分）。Cloud Scheduler の有効化に初回数分かかることがあります。
