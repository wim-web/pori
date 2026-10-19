# Pori — Mac用ファイル転送アプリ（試作）

AndroidにはUSB、iPhone / iPadにはAirDropでファイルを送る、SwiftUI製のMacアプリです。Apple Silicon / macOS 14以降に対応しています。

## ビルドして使う

XcodeのSwiftコンパイラと、Apple Silicon版の[OpenMTP](https://github.com/ganeshrvel/openmtp)を用意してください。試作ではOpenMTP 3.3.0のエンジンを使用しています。

```sh
git clone https://github.com/wim-web/pori.git
cd pori
bash build.sh
open Pori.app
```

リポジトリにはソースを収録しています。`build.sh` は `/Applications/OpenMTP.app` から転送エンジンを読み取り、生成する `Pori.app` にコピーします。元のOpenMTPは変更しません。ビルド後はOpenMTPを起動せずに使えます。

## iPhone / iPadに送る

1. Finderからファイルやフォルダを中央の枠にドロップするか、「ファイルを選ぶ」で追加します。
2. 「iPhone / iPad」を選び、「AirDropを開く」を押します。
3. macOS標準のAirDrop画面で相手を選びます。

送り先に追加アプリは不要です。近くにあるMacにも送れます。保存先の扱いは通常のAirDropと同じで、PoriからiPhone内のフォルダを指定することはできません。

macOSからのコールバックだけでは相手での受信完了を判定できないため、Poriは「送信完了」を表示せず、追加したファイルも自動削除しません。受信結果は相手の端末で確認してください。キャンセル後はそのまま再試行できます。

## AndroidとUSBでやり取りする

1. OpenMTPなど、端末を使っているほかのMTP転送アプリを終了します。
2. Androidをデータ通信対応ケーブルで接続し、ロックを解除します。
3. Android側のUSB設定を「ファイル転送」にします。
4. Poriで「USB接続する」を押します。
5. 「Androidのファイル」でフォルダをダブルクリックして開きます。
6. 送る場合は「このフォルダへ送る」からファイルを追加して「Androidへ送る」。Macに取り込む場合は項目を選んで「選択項目をMacに保存」。

Androidは1台ずつ接続します。USB送信は同名項目があると停止します。Macへの保存は指定先に毎回新しい `Pori-日時-識別子` フォルダを作るため、既存ファイルと混ざりません。シンボリックリンクや特殊ファイルのUSB送信は拒否します。

中止・切断時には転送途中のファイルが残る場合があります。確認してから再試行してください。履歴は起動中のメモリ内だけに保存します。

## 実装と再ビルド

- UI: SwiftUI + AppKit。ネイティブのMacアプリです。
- AirDrop: `NSSharingService(.sendViaAirDrop)`。
- USB: OpenMTP 3.3.0のKalam / libusbを別プロセスのObjective-Cブリッジ経由で呼び出します。
- `Sources/`: Swiftソース。`Native/`: USBブリッジ。`Tests/`: テスト専用の転送エンジン模擬実装。
- テスト用ファイルは `Samples/お試し.txt`。

XcodeのSwiftコンパイラと、`/Applications/OpenMTP.app` のarm64エンジンがあれば `bash build.sh` で再ビルドできます。別のエンジン配置は `PORI_ENGINE_DIR` で指定できます。ローカル用のアドホック署名を付与します。App Store配布や公証は行っていません。

```sh
bash build.sh
python3 Tests/protocol-test.py
```

通常起動時にテスト用エンジンを使う経路はありません。アプリは同梱された実際のKalamを使用します。

## 検証範囲

ビルド、署名、ストレージとファイル情報の解釈、4GB超のサイズ、日本語名、同名衝突・不完全な存在確認の拒否、シンボリックリンクの拒否を検証しています。ネイティブブリッジは模擬ライブラリでコールバック、進捗、エラー、連続リクエストを検証します。

実際のMac画面で起動、ファイル選択、AirDrop小窓の表示・キャンセル、Android未接続時のエラーを確認しています。実機間の転送完了と、Android接続中の閲覧・送受信は未検証です。

## ライセンス

第三者ライセンスは `Licenses/` とアプリ内 `Contents/Resources/Licenses/` に同梱しています。エンジンの出典と差し替え方法は `Licenses/NOTICE.txt` を参照してください。
