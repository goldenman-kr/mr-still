# 구현·검증 기록

## 한국어·영어 지원 및 로컬 설치

메뉴, 안내, 오류, 상태바, 정보창, 툴팁과 접근성 문구를 en/ko Localizable.strings로 분리했다. 앱별 언어와 시스템 선호 언어 선택은 Bundle에 맡기고 지원 언어가 없는 경우 영어로 대체한다. Swift Package와 Xcode 빌드 모두 번역 리소스를 포함한다. 파일명·폴더명·원본 메타데이터는 번역하지 않는다. 영어 정렬 항목을 위해 팝업 너비를 조정했다.

Release 빌드를 완료하고 기존 앱을 백업한 뒤 `/Applications/Mr. Still.app`에 설치했다. 빌드/설치본 서명과 한국어·영어 리소스 포함 여부만 확인했다. 사용자 요청에 따라 자동 테스트, 언어 전환 실행 확인 및 기능/UI 검증은 수행하지 않았다. GitHub 푸시 및 릴리스 갱신은 하지 않았다.

백업 `build/Verification/MrStill-before-localization.zip`, 빌드 로그 `build/Verification/localization-build.log`.

---

## 2026-10-23 v1.0.0 DMG 배포

README의 앱 식별자 표기를 제거하고 macOS 14+ 설치 절차, Releases 링크와 첫 실행 안내를 추가했다. 버전을 1.0.0으로 지정하고 이미 빌드한 앱을 Applications 링크와 함께 DMG로 묶는 스크립트를 추가했다.

배포 앱은 arm64/x86_64 Universal Release로 빌드했다. 디버그 심볼의 개인 빌드 경로를 제거한 뒤 Developer ID로 hardened runtime 및 보안 타임스탬프를 포함해 재서명했다. 사용자가 공증 없이 진행하도록 지시했으며 README와 릴리스 설명에 미공증 상태를 명시한다. 인증서·비밀번호·개인키는 소스에 포함하지 않는다.

앱 및 DMG의 strict 서명, DMG 체크섬을 검증했다. 읽기 전용 마운트에서 앱 버전 1.0.0, 두 아키텍처, Applications 링크와 앱 서명을 확인했다. 앱 파일의 개인 홈 경로·이메일·토큰 표식 검사와 변경 파일의 공백 검사를 통과했다. Intel Mac 및 macOS 14 실기기 실행은 검증하지 않았다. 기능 소스는 직전 전체 71개 테스트를 통과한 버전과 동일하다.

---

## 2026-10-23 공개 저장소 준비

빌드 결과물, 개인 Xcode 설정, 에이전트 작업 기록, 인증서·개인키 및 개인 폴더가 보이는 스크린샷을 공개 대상에서 제외했다. 문서의 개인 이메일·서명 계정 정보와 성능 자료의 개인 절대경로를 제거했다. 프로젝트와 생성기는 기본 ad-hoc 서명을 사용하며 개발자 서명은 명령행에서 지정할 수 있다. 앱 식별자는 유지한다.

전체 테스트 71개(Core 21 + App 50)와 공개 기본 설정의 Release 빌드를 통과했다. 공개 대상 37개 파일에 대해 토큰·개인키·개인 경로 검사를 수행했으며 검출된 항목이 없다. 빌드 스크립트 문법, 제외 규칙과 diff 공백 검사도 통과했다.

---

## 2026-10-23 즐겨찾기 제목 더블클릭

트리 더블클릭 처리에서 URL이 없는 그룹을 제외하던 조건을 제거하고 실제 펼칠 수 있는 항목인지로 판별한다. 즐겨찾기 제목도 등록된 폴더가 있으면 더블클릭으로 펼침·접힘을 전환하며, 비어 있으면 무시한다. 제목 조작으로 표시 폴더나 파일 선택을 바꾸지 않는다.

즐겨찾기 관련 테스트 7개, Release 빌드 및 설치 전후 strict 서명 검사 통과. 설치 앱에서 즐겨찾기 제목을 실제 더블클릭해 collapsed, 다시 더블클릭해 expanded 상태로 전환됨을 확인했다.

설치 `/Applications/Mr. Still.app`, 백업 `build/Verification/MrStill-before-favorites-heading.zip`, 로그 `favorites-heading-tests.log`, `favorites-heading-release.log`.

---

## 2026-10-23 중복 폴더의 트리 선택 위치 유지

DirectoryTreeController.show가 즐겨찾기 경로를 우선 탐색해 동일 URL의 일반 트리 노드 선택을 즐겨찾기로 옮기던 문제를 수정했다. 현재 선택 노드의 URL이 표시 폴더와 같으면 해당 노드를 유지한다. 수동 선택은 진행 중인 비동기 reveal 세대를 취소해 이전 탐색 완료가 새 선택을 덮어쓰지 않게 한다. 경로 표시는 정상 갱신하며 선택이 없는 외부 열기의 기존 경로 탐색은 유지한다.

수정 전 회귀 테스트에서 일반 트리 선택이 즐겨찾기로 이동하는 실패를 재현했다. 수정 후 일반 트리→즐겨찾기→일반 트리 및 각각의 Nested 하위 선택/새로고침에서 동일 노드 identity 유지 검증을 포함해 전체 70개(Core 21 + App 49) 테스트 통과. Release 빌드와 설치 전후 strict 서명 검사 통과. 실제 설치 앱의 Home 아래 Pictures 선택은 해당 일반 트리에 유지되고, 즐겨찾기 Pictures 선택은 그 위치에 유지됨을 확인했다.

설치 `/Applications/Mr. Still.app`, 백업 `build/Verification/MrStill-before-tree-selection.zip`, 로그 `tree-selection-tests.log`, `tree-selection-release.log`.

---

## 2026-10-23 목록 셀 세로 정렬 및 헤더 정렬

크기·수정일을 NSTableCellView 내부의 centerY 제약이 있는 텍스트로 변경해 파일명과 같이 행 중앙에 표시한다. 이름·크기·수정일 열에 오름차순 sortDescriptorPrototype을 제공하고, 네이티브 헤더 클릭의 sortDescriptorsDidChange를 BrowserModel.setSort에 연결했다. 다른 열은 오름차순으로 시작하고 같은 열은 오름/내림을 토글한다. 툴바와 헤더 표시를 양방향 동기화하며 동기화 중 콜백은 재진입하지 않는다. 파일 선택은 유지한다.

전체 테스트 69개(Core 21 + App 48), Release 빌드 및 설치 전후 strict 서명 검사 통과. 세 열의 실제 셀 텍스트 centerY, 모든 기준/방향의 정렬 결과·선택 유지·헤더/툴바 동기화를 회귀 테스트로 검증했다. 설치 앱에서 크기 헤더 첫 클릭 오름차순, 재클릭 내림차순, 수정일 클릭 오름차순을 확인했다. 파일이 있는 목록의 스크린샷에서도 이름·용량·수정일의 세로 중앙 배치를 확인했다.

설치 `/Applications/Mr. Still.app`, 백업 `build/Verification/MrStill-before-list-columns.zip`, 로그 `list-columns-tests.log`, `list-columns-release.log`.

---

## 2026-10-23 선택과 무관한 정렬 메뉴

FileBrowserController의 메뉴 검증 기본값이 모든 항목에 선택 필수 조건을 적용해 NSPopUpButton 정렬 항목도 비활성화했다. 선택 조건은 Finder 표시·복사·삭제 등 파일 작업에만 적용하고 정렬 메뉴는 항상 허용한다. 회귀 테스트가 수정 전 실패하고 수정 후 통과함을 확인했다. 세 보기 방식의 미선택 및 빈 폴더에서 정렬 옵션/방향 변경을 검증했다.

전체 테스트 68개(Core 21 + App 47), Release 빌드, strict 서명 검사를 통과했다. `/Applications/Mr. Still.app` 설치 후 아무 파일/폴더를 열지 않은 상태에서 정렬 메뉴 활성화, 크기로 변경, 내림차순 전환을 실제 확인하고 원래 이름·오름차순 설정으로 복원했다. 로그 `build/Verification/sort-selection-tests.log`, `sort-selection-release.log`, 백업 `MrStill-before-sort-fix.zip`.

---

## 2026-10-23 트리 더블클릭과 상태바 파일 용량

화면1은 클릭한 폴더 행의 더블클릭을 disclosure 펼침/접힘에 연결한다. 한 단계만 펼치며 빈 영역·즐겨찾기 제목·하위 폴더가 없는 항목은 무시한다. 비동기 조회 결과 하위가 없으면 펼침 상태를 정리한다. 화면3은 파일명 · 원본 해상도 · 파일 용량(KB/MB 등)을 표시한다. 용량은 이미 조회한 ImageFile 정보를 사용하며 확대·축소 후에도 유지한다.

전체 67개 테스트 통과 후 빈 폴더 처리에 대한 최종 폴더 테스트 8개를 다시 통과했다. Release 빌드 및 설치 전후 strict 서명 검사 통과. 설치된 앱에서 Pictures 더블클릭 펼침/다시 더블클릭 접힘과 `1426 × 950 · 374 KB` 표시를 확인했다. 설치 경로 `/Applications/Mr. Still.app`, 백업 `build/Verification/MrStill-before-tree-doubleclick.zip`, 로그 `tree-and-size-tests.log`, `tree-final-tests.log`, `tree-and-size-release.log`.

---

## 2026-10-23 폴더 탐색 도구 모음과 이동 메뉴

경로 헤더의 뒤로/앞으로를 테두리 없는 arrow.left/right로 바꾸고 arrow.up과 arrow.clockwise 버튼을 추가했다. 편집과 보기 사이에 이동 메뉴를 추가하고 네 동작을 동일한 BrowserModel 메서드에 연결했다. 메뉴의 뒤로/앞으로는 Option+좌/우 화살표 key equivalent를 선언한다. 기존 창 전체 입력 처리는 유지한다.

상위 폴더 이동은 방문 기록에 포함되고, 루트 및 로딩 중에는 비활성화된다. 새로고침은 선택과 앞으로 기록을 보존하며 현재 폴더의 트리 노드도 재조회한다. 파일 감시와 동일한 요청 세대 검사를 사용한다.

전체 테스트 66개(Core 21 + App 45), Release 빌드와 설치 전후 strict 서명 검사가 통과했다. 실제 설치 앱에서 네 버튼의 접근성·활성화, Desktop에서 위로 이동해 홈 경로와 목록 갱신, 새로고침 후 선택 유지, 이동 메뉴의 네 항목을 확인했다. CUA 스크린샷은 unavailable을 반환해 픽셀 단위 외형 검증은 하지 못했다. 테두리 제거와 버튼 겹침 방지는 AppKit 테스트로 확인했다.

설치: `/Applications/Mr. Still.app`. 번들 식별자 유지. 백업: `build/Verification/MrStill-before-navigation-toolbar.zip`. 로그: `build/Verification/navigation-toolbar-tests.log`, `navigation-toolbar-release.log`.

---

## 2026-10-23 Mr. Still 이름 변경

표시 이름, 앱 메뉴·창 제목·정보창·기본 앱 설정 결과 문구와 제품 번들을 Mr. Still로 변경했다. 번들 식별자 `photoviewer.app.kryp.xyz`, 개발자 서명, 문서 형식 선언과 내부 설정 키는 유지한다. 내부 Swift 모듈/타깃 이름은 PhotoViewer를 유지한다.

Release 빌드·strict 서명 검사와 기본 앱 서비스 테스트 4개를 통과했다. `/Applications/Mr. Still.app`으로 설치하고 이전 Photo Viewer 앱은 ZIP으로 백업했다. 실제 실행의 앱 이름·창 제목·상단 메뉴에서 Mr. Still을 확인했다.

변경 전후 NSWorkspace의 기본 앱 조회를 비교했다. JPEG/PNG/HEIC/HEIF/TIFF/BMP/GIF 모두 변경 전 `/Applications/Photo Viewer.app`에서 변경 후 `/Applications/Mr. Still.app`으로 해석되며 번들 식별자는 동일하다. 기본 앱 설정 API를 호출하지 않고 Launch Services 등록만 갱신했으므로 파일 연결 재설정이 필요하지 않았다. Apple도 Launch Services가 앱을 찾는 데 번들 식별자를 사용한다고 명시한다: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier

검증 로그: `build/Verification/rename-release.log`, `rename-tests.log`, `rename-handlers-before.txt`, `rename-handlers-after.txt`. 이전 앱 백업: `build/Verification/PhotoViewer-before-rename.zip`.

---

## 2026-10-22 폴더 뒤로·앞으로 탐색

경로 표시줄 왼쪽에 뒤로/앞으로 아이콘을 추가하고 세 화면·슬라이드·전체화면의 공통 Option+좌우 화살표와 마우스 보조 버튼 3/4에 연결했다. 기존 수정키 없는 사진 화살표 이동 및 Option+스크롤 배율 조작과 분리하며, 배율 입력 중 Option+화살표는 텍스트 편집을 유지한다. [Apple의 로컬 이벤트 모니터](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:))를 사용해 앱 창에서만 처리한다. 마우스 down/up은 한 번만 이동시키고 가운데 버튼은 처리하지 않는다. 다른 창·시트·모달에는 적용하지 않는다.

폴더는 읽기 성공 후 화면과 기록에 반영된다. 같은 폴더 새로고침/정렬/같은 폴더의 파일 열기는 중복 기록하지 않고, 뒤로 이동 후 새로운 폴더 탐색은 앞으로 분기를 교체한다. 실패하거나 뒤늦게 완료된 이전 요청은 현재 폴더·파일·선택·기록을 덮어쓰지 않는다. 폴더 감시의 새로고침도 진행 중인 사용자 이동을 덮어쓰지 않는다. 기록은 실행 세션에 한하며 도착 폴더의 현재 정렬 기준 첫 이미지를 선택한다.

자동 테스트 **65개 통과**(Core 21 + App 44). 신규 9개는 히스토리 6개와 입력/UI 3개로 정상 왕복·끝 경계·새 분기·중복 방지·실패·비동기 경합·외부 파일 열기·헤더 버튼 활성화·세 화면 포커스·슬라이드/전체화면·키 반복·텍스트 편집·시트 보호를 검증한다. 실제 NSEvent로 표준 마우스 버튼 번호를 검증하고, controller 이벤트 테스트에서 down/up 중복 이동을 확인했다. 실제 하드웨어 마우스 보조 버튼은 도구가 지원하지 않아 실기 클릭은 미검증이다.

설치 앱에서 Documents → Desktop 이동 후 Option+왼쪽으로 Documents 복귀, 앞으로 아이콘으로 Desktop 복귀와 경로/트리/사진 갱신을 확인했다. 스크린샷에서 두 아이콘이 경로 왼쪽에 있고 경로·트리와 겹치지 않음을 확인했다. Release 빌드·strict 서명 검사 통과 후 `/Applications/Photo Viewer.app`에 업데이트했고 빌드/설치 실행 파일 해시가 일치한다. 기본 이미지 앱 설정은 변경하지 않았다.

로그: `build/Verification/history-all-tests.log`, `history-input-tests.log`, `history-release.log`. 이전 설치본 백업: `build/Verification/PhotoViewer-before-history.zip`.

---

## 2026-10-22 모드 전환 레이아웃 복구·기본 이미지 앱 메뉴

화면2 더블클릭 후 슬라이드/전체화면 크기가 깨지는 경로를 회귀 테스트로 재현했다. 기존 코드는 뷰어를 NSSplitView의 arrangedSubview에서 제거했다. 숨겨진 분할창은 남은 왼쪽 패널을 창 전체 너비(테스트에서 1,600pt)로 늘렸고, 복귀 후 뷰어 너비가 기대 916pt 대신 400pt가 되는 오류와 제약 충돌을 기록했다. 수정 전 신규 테스트는 assertion 4개 실패, 수정 후 통과한다.

고정된 오른쪽 호스트를 분할창에 유지하고 실제 뷰어만 호스트/최상위 컨테이너 사이에서 이동한다. 숨겨진 분할창의 자동 크기 변경도 멈추므로 왼쪽 패널 크기가 전체화면 너비로 변하지 않는다. 목록/썸네일 더블클릭은 클릭한 항목을 먼저 선택한 뒤 공통 슬라이드 진입을 호출한다.

자동 테스트 **56개 통과**(Core 21 + App 35), 레이아웃 제약 충돌 경고 0건. 새로운 회귀 검증은 반복 모드 전환, 슬라이드에서 1600×1000/420×340 크기 변경, 전체화면 1920×1080 왕복과 왼쪽 너비 유지, 세 표시 모드의 클릭 파일 선택 및 화면3 더블클릭과 동일한 프레임을 포함한다. 기존 최소 크기·4pt 분할선 테스트도 통과했다. Release 빌드와 strict 서명 검증 통과 후 `/Applications/Photo Viewer.app`을 업데이트했다. Xcode의 AppIntents 미사용 메타데이터 추출 생략 메시지만 남아 있다.

실제 설치 앱에서 목록의 다른 이미지 더블클릭 → 슬라이드 → F 전체화면 → F 슬라이드 복귀 → 이미지 더블클릭 탐색기 복귀를 확인했다. 큰 썸네일 더블클릭도 해당 이미지를 표시했다. 슬라이드 창을 684×1150에서 1200×800으로 조절한 뒤 탐색기로 돌아와 왼쪽 280pt가 유지되고 이미지 영역이 나머지를 차지하는 화면을 확인했다. 세로 분할선이 이미지에 나타나지 않는다.

‘파일 → 기본 이미지 앱으로 설정’ 메뉴를 실제 앱에서 확인했다. macOS 공식 [NSWorkspace API](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopen:completion:))로 JPEG, PNG, HEIC, HEIF, TIFF, BMP, GIF를 순차 설정하고 이미 설정된 항목은 건너뛴다. 완료 후 OS의 기본 앱 경로를 확인하고 취소/실패를 형식별로 안내한다. 테스트 4개는 주입한 setter/reader로 전체 형식·순차 호출·부분 실패·번들 선언 일치를 검증했다. 실제 기본 앱 변경과 OS 동의창은 실행하지 않았으며, 사용자가 메뉴를 누를 때 실행된다.

로그: `build/Verification/mode-before.log`, `mode-all-tests.log`, `mode-release.log`. 업데이트 전 앱은 `build/Verification/PhotoViewer-before-mode-fix.zip`에 백업했다.

---

## 2026-10-22 썸네일 균등 간격·4pt 분할선·설치

썸네일 셀의 좌우 여백과 열 사이 간격을 동일하게 계산하며 너비/표시 모드 변경 때 갱신한다. 마지막 줄은 위쪽 열에 정렬된다. 기존 Flow Layout의 고정 8pt 여백과 내부 간격 확장 동작이 중앙의 과도한 공간을 만들었다([Apple 간격 문서](https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/minimuminteritemspacing)). 분할선은 사용자 추가 요청에 따라 4pt로 줄였고 탐색기 최소 크기는 684×404pt다.

새 회귀 테스트는 기존 코드에서 52개 assertion 실패로 문제를 재현했다. 수정 후 작은/큰 썸네일 전환, 300/400/420/550/565pt 너비 및 축소 복귀, 마지막 줄 정렬 검증을 통과했다. 전체 자동 테스트 **50개 통과, 실패/건너뛰기 0**. 이전부터 기록한 모드 전환 Auto Layout 경고 1건은 동일하게 남아 있으나 크기·계층 테스트는 통과한다.

Release 빌드 및 설치 전후 strict 서명 검증을 통과했다. 사용자 명시 요청에 따라 **/Applications/Photo Viewer.app**에 설치했고, 설치본을 실행하여 2/3/4열 배치와 실제 4pt 분할선 드래그를 직접 확인했다. 확인 후 왼쪽 패널 너비를 기존 402pt로 복원했다. 개인 파일 화면 캡처는 문서에 저장하지 않았다. 앱 식별자는 `photoviewer.app.kryp.xyz`, 개발자 서명은 기존 로컬 개발자 계정이다. 빌드 복사본의 Launch Services 등록을 해제하고 Applications 설치본을 등록했다. 기본 이미지 연결 앱은 변경하지 않았다.

로그: `build/Verification/install-tests.log`, `install-release.log`, `spacing-before.log`.

---

## 2026-10-22 폴더 탐색·키보드·앱 식별자 수정

화면2의 하위 폴더 표시와 더블클릭/Return 이동, 경로 배경 구분, 6pt 분할선, 홈 1단계 펼침, 한글 입력에서 물리 I/F 키 처리, 앱 이름/식별자를 반영했다. 앱 이름은 **Photo Viewer**, 번들 식별자는 **photoviewer.app.kryp.xyz**다. 이전 Review/FinalCheck/Smoke 및 구 Debug 앱 번들을 작업 폴더에서 제거했다. Applications 설치나 기본 연결 프로그램 변경은 하지 않았다.

자동 테스트 **49개 통과, 실패/건너뛰기 0**: 기존 38개에 폴더/트리 7개와 키보드/분할선 4개를 추가했다. 폴더 우선 정렬, 이미지 전용 탐색, 폴더 활성화, 이미지 선택 복원, 트리 동기화, 얕은 초기 펼침, 조회만으로 펼쳐지지 않음, 로딩 중 접기 유지, 한글 문자 이벤트의 물리 키 매핑, 텍스트 편집 보호, 다른 창 제외, 키 반복 방지, 686×406pt 최소 크기와 각 패널 최소값을 검증했다. 폴더 포함 선택에서는 복사/휴지통 이동이 비활성화되며 붙여넣기는 일반 이미지 파일만 허용한다.

새 Release 앱의 실제 화면에서 Photo Viewer 이름, 경로 배경과 6pt 분할선, 홈의 직속 폴더만 펼쳐지는 상태를 확인했다. 후속 접근성 상태에서도 Documents 아래 폴더 17개와 사진 2개가 화면2에 같이 나타나는 것을 확인했다. 한글 입력 소스에서 실제 키보드로 I/F를 누르는 종단 검증과 폴더 더블클릭/Return의 실기 검증은 자동화 도구의 열기 대화상자 시간 초과로 완료하지 못했다. 해당 동작은 합성 NSEvent 및 AppKit 컨트롤러 회귀 테스트로 검증했다.

키보드 처리는 [Apple의 로컬 이벤트 모니터 API](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:))를 사용하여 입력기 전달 전 물리 키를 해석한다. 분할선 두께는 [NSSplitView.dividerThickness](https://developer.apple.com/documentation/appkit/nssplitview/dividerthickness)를 재정의했다. 트리 펼침 여부 질의에서 비동기 완료 후 무조건 펼치던 부작용을 제거했다.

검증 로그: `build/Verification/navigation-tests.log`, `navigation-release.log`. Release 빌드 및 최종 앱의 strict 서명 검증을 통과했다. `CFBundleName`/`CFBundleDisplayName`은 Photo Viewer, `CFBundleIdentifier`는 photoviewer.app.kryp.xyz임을 확인했고 작업 폴더에는 Release 앱 한 개만 남았다. 모드 전환 회귀 테스트에서 일시적인 Auto Layout 충돌 경고 1건은 남아 있으나, 모든 크기·계층 검증은 통과했다. 실제 한글 입력 전환과 함께 추가 실기 확인이 필요한 범위로 기록한다.

---

## 2026-10-22 추가 수정 검증

상태바 전체 우측 정렬, 정보 테이블, 즐겨찾기 저장 및 디렉터리/파일 Finder 메뉴, 슬라이드 더블클릭 복귀, 세로선 수정, 앱 아이콘을 반영했다. 최종 자동 테스트 **38개 통과, 실패/건너뛰기 0**. Release 빌드와 지정 개발자 인증서의 strict 서명 검증을 통과했고 앱 번들의 `CFBundleIconFile = AppIcon`, `Contents/Resources/AppIcon.icns` 포함을 확인했다.

추가 테스트 9개는 즐겨찾기 5개, 뷰어/정보 테이블 3개, 모드별 뷰 계층 회귀 1개다. 상태바 우측 정렬은 400/1000/1600pt 너비에서, 슬라이드 전환과 왼쪽 너비 복원은 1200/1352/681/800pt 너비에서 검증했다. 정보 테이블은 전체 항목과 긴 값 보존을 확인했다. Finder 메뉴는 우클릭 대상 URL을 검증했으며 외부 Finder 실행 자체는 테스트하지 않았다.

첨부 세로선은 이전 왼쪽 패널 경계 위치와 일치했다. 기존 코드는 왼쪽 뷰만 숨긴 뒤 뷰어를 `NSSplitView` 안에서 확장했다. `shouldHideDividerAt`은 분할선의 드래그/접힘 동작에 관한 API이며 임의 프레임 변경 후 그리기를 끄는 스위치가 아니다([Apple 문서](https://developer.apple.com/documentation/appkit/nssplitviewdelegate/splitview(_:shouldhidedividerat:))). 수정본은 슬라이드/전체화면 동안 전체 분할 뷰를 숨기고 뷰어를 일반 컨테이너로 옮긴다. 원래 컨트롤러를 임시 복사본에 넣어 동일 회귀 테스트를 실행하면 9개 assertion이 실패하며, 수정본은 모두 통과한다. 이는 분할선이 뷰어 계층에 남는 경로와 수정 효과를 검증한다.

새 아이콘은 512px/16px 미리보기를 직접 확인했다. 실제 검증용 앱에서 즐겨찾기가 홈 위에 있는 접근성 트리도 확인했다. 이후 UI 자동화 도구가 파일 열기 창에서 반복 시간 초과되어 새 정보 테이블과 슬라이드의 최종 화면 캡처는 완료하지 못했다. 실제 창의 픽셀 단위 재검증은 남아 있으며, 이 범위를 자동 테스트 통과와 구분한다. offscreen 캡처는 네이티브 레이어를 완전하게 재현하지 않아 시각 증거로 사용하지 않았다.

이번 로그: `build/Verification/enhancements-tests.log`, `enhancements-release.log`, `divider-before-regression.log`. 아래는 최초 구현의 검증 이력이다.

---

2026-10-22. 1차 구현 및 로컬 서명 빌드 완료. Applications 설치와 기본 이미지 앱 변경은 수행하지 않았다.

## 환경과 산출물

- Apple M4, 메모리 24GiB, macOS 26.6.2, Xcode 27.0 / Swift 6.4 (Swift 5 언어 모드).
- 지원 타깃 macOS 14.0. 이번 Release 산출물은 arm64이며 실제 실행은 위 환경에서 확인했다.
- 앱: `build/DerivedData/Build/Products/Release/Photo Viewer.app`
- 서명: `Apple Development (local signing identity)`, hardened runtime.
- 최종 Release `xcodebuild` 성공. `codesign --verify --deep --strict` 결과 `valid on disk`, `satisfies its Designated Requirement` 확인. 공증은 수행하지 않았다.
- 샌드박스 안에서는 시스템 키체인 접근 제한으로 인증서 조회/검증이 실패했다. 시스템 접근이 가능한 실행에서 인증서 체인과 최종 서명을 확인했다.

## 자동 검증

최종 `swift test --disable-sandbox`: **29개 실행, 실패 0, 건너뛰기 0**.

| 영역 | 수 | 확인한 동작 |
| --- | ---: | --- |
| Models | 11 | 자연 정렬/동률, 양방향 정렬, Fit/Retina/작은 이미지, 극소 배율, 두 자리 표시와 입력 검증, 창 너비 우선순위/최소값 |
| Services | 10 | 비재귀 폴더 열거, 숨김/비이미지 필터, 선언 포맷 디코딩, EXIF 방향, GPS/EXIF 중첩 속성, 손상 이미지 오류, 썸네일 캐시 갱신/메인 콜백, 동명 복사와 부분 실패, 없는 파일 휴지통 오류 |
| App state | 5 | 비동기 새로고침 중 최신 선택 유지, 숨김 파일 직접 열기/없는 최근 파일 오류, 정렬 후 대표 선택과 탐색, 전체화면 진입 전 모드 복원, 하단 호버 시 캔버스 크기/배율 불변 |
| Print | 3 | 최종 인쇄 설정 적용, 용지·여백 변경에도 1페이지, 실제 세로/가로 PDF의 페이지 크기·이미지 비율·최대 Fit·중앙 정렬 |

HEIC 생성은 제한된 실행 환경에서는 VideoToolbox 접근 문제로 건너뛰었으나, 시스템 인코더를 이용할 수 있는 최종 실행에서는 HEIC/HEIF 테스트가 통과했다. 인쇄 테스트는 합성 이미지를 임시 PDF로 저장·검사하고 정리했으며 실제 프린터로 보내지 않았다.

## 화면과 검토

- 합성 사진으로 실제 앱 실행, 3분할 레이아웃, 다크 테마, 썸네일/사진 Fit, 상태바 배치를 확인했다. 초기 화면은 로컬 검증 자료에 보존했다. 개인 폴더 정보가 포함된 스크린샷은 공개 저장소에서 제외한다.
- 최종 앱 접근성 트리에서 상태바가 배율 → Fit → 모드 → 전체화면 → **이미지 정보 (I)** 순서임을 확인했다. 소스에서 I 키의 무수정키 메뉴 할당과 편집 가능한 텍스트 우선 처리를 확인했다.
- 마지막 직접 UI 자동화 중 화면 상태 변경과 도구 시간 초과가 발생해 사용자 조작과 겹칠 수 있는 추가 입력은 중단했다. 최종 I 키 실제 입력 및 전체화면 마우스 호버의 종단 UI 재검증은 아직 완료로 간주하지 않는다. 호버 표시/숨김과 Fit 불변은 AppKit 컨트롤러 테스트로 확인했다.
- 별도 읽기 전용 검토에서 발견한 새로고침 선택 경합, 전체화면 원래 모드 복원, 신규 하위 폴더 트리 공개, 없는 최근 파일 처리, 인쇄 용지 변경 후 Fit 문제를 수정했다.
- 전용 visual-verdict 스킬이 로컬에 없어 직접 화면 검토와 `.omx/state/photo-viewer/ralph-progress.json`으로 근거를 기록했다. offscreen 뷰 캡처는 네이티브 레이어/심볼을 완전히 재현하지 않아 최종 시각 판정 근거로 사용하지 않았다.

## 성능 측정

최적화된 독립 실행 파일에서 각 작업을 별도 프로세스로 측정했다. 1회 준비 실행 뒤 20회 측정하며 파일시스템 캐시를 비우지 않았다. 10,000개 목록은 하나의 합성 6000×4000 JPEG에 대한 하드링크이며, 개인 사진은 사용하지 않았다. 원시 샘플/환경은 [performance.json](performance.json), 재현 코드는 `scripts/benchmark.swift`에 있다.

| 작업 | 중앙값 | p95 | 작업 프로세스 최대 RSS |
| --- | ---: | ---: | ---: |
| 10,000개 파일 메타데이터 열거 + 자연 이름 정렬 | 329.17ms | 358.62ms | 110.02MiB |
| 24MP JPEG → 긴 변 1600px 디코딩 | 29.21ms | 30.67ms | 140.80MiB |
| 24MP JPEG 원본 디코딩 | 64.98ms | 127.93ms | 314.42MiB |

이는 서비스 처리 시간과 해당 벤치마크 프로세스의 메모리다. 실제 사진 10,000개로 구성한 폴더, 화면 전환 지연, 그리드 전체 채움, 메인 스레드 정지 시간, 앱 전체 메모리 또는 장시간 안정성을 검증한 수치가 아니다. 계획의 UI 전환 p95 100ms 목표는 아직 계측하지 않았다.

## 남은 검증·범위

- macOS 14/15, Intel, 다중 모니터 이동, 접근성 보조 장치, 색상 프로파일별 디스플레이 정확성은 별도 실기 검증이 필요하다.
- 실제 프린터 출력, Finder 기본 앱 연결/포맷별 Quick Look, 파일 URL 클립보드와 Finder의 왕복, 성공한 휴지통 이동/복원, 네트워크 볼륨 및 장기 반복 메모리 검증은 자동 테스트 결과에 포함하지 않았다.
- GPS 지도, RAW/영상/이미지 편집, 자동 슬라이드 재생, GIF 애니메이션, 제조사별 독자 메타데이터 완전 해석은 이번 범위 밖이다.
- 뷰어 상세 디코딩은 128MP/긴 변 32,768px 상한을 적용한다. 넘는 사진은 상태바에 해상도 제한을 표시한다.
- 사용자 검수 후 별도 설치 지시가 오면 Applications 배치를 진행한다.

최종 실행 로그는 `build/Verification/final-tests.log`, `build/Verification/final-release.log`에 보관했다.


## App Store 준비 변경 검증 (2026-10-24)

이 항목은 기존 일반 배포 검증과 구분한 App Store 전용 구성의 결과다.

- 전체 Swift 테스트 **84개 통과**: Core 21개, AppKit 63개. 파일 접근 신규 테스트 13개는 북마크 복원/갱신, 이동 후 두 번 재실행, 갱신 실패 데이터 보존, 중복 scope 해제, 심볼릭 링크 경계, 선택 취소·쓰기 제한, 복사 임시 권한을 검증한다.
- `AppStoreDebug` Apple Development 서명 빌드 성공. 서명에서 sandbox·사용자 선택 read/write·app-scope bookmark·printing 권한 확인, strict signature 검증 통과. 개발 빌드의 get-task-allow는 제출용 아카이브 권한에 포함되지 않는다.
- 실제 해당 앱의 macOS UI에서 합성 Fixtures 폴더 승인, 이미지 표시, 같은 폴더 복사/붙여넣기(둘 다 유지), 생성된 복사본만 휴지통 이동, 시스템 인쇄 패널의 한 페이지 미리보기, 종료 후 북마크 복원 및 추가 승인 없는 재열기를 확인했다. 실제 프린터 출력은 하지 않았다.
- 일반 `Release` 빌드 성공. App Store `AppStore` 로컬 아카이브 성공, 실행 파일의 arm64/x86_64와 번들 내 privacy manifest·영어/한국어 정책 리소스를 확인했다.
- 최종 아카이브는 `build/AppStore/Mr.Still-final.xcarchive`이다. 서명되지 않은 **로컬 검증 결과**이며 App Store Connect 업로드 가능한 배포 아카이브가 아니다. 개발용 앱 실행 검증도 TestFlight/심사 통과를 뜻하지 않는다.
- 실제 Finder와의 외부 클립보드 왕복, Finder에서 외부 파일 열기, 권한의 OS 차원 철회, Intel/macOS 14 실기, TestFlight, 최종 배포 프로비저닝은 미검증이다. 관련 동작은 자동 테스트·소스 검토와 구분한다.
- 이번 작업은 Applications의 기존 앱 교체, GitHub 릴리스, App Store 제출을 수행하지 않았다. 로그는 `build/Verification/AppStore/`에 보관한다.


## 홈 탐색 추가 (2026-10-24)

- 샌드박스 트리에도 즐겨찾기 다음에 홈을 항상 표시하고, 경로 표시줄의 새로고침 옆에 홈 버튼을 추가했다. 앱 컨테이너 대신 사용자 계정의 실제 홈 경로를 사용하며, 경로 조회 자체로 접근 권한을 부여하지 않는다.
- 승인 전 자동 열거/자동 요청 없음, 펼침 시 승인 취소, 홈 버튼 최초 승인과 재사용, 홈 중복 루트 방지, 직속 폴더만 펼침을 추가 테스트로 확인했다. 전체 86개 테스트 통과.
- AppStoreDebug 서명 빌드와 설치본 교체·서명 검증을 완료했다. 설치 앱의 접근성 트리에서 홈 항목과 홈 버튼, 홈 직속 폴더의 하위 펼침 해제 상태를 확인했다.


## 경로 표시줄 편집·폴더별 이동 (2026-10-24)

- 고정 높이의 텍스트 라벨 대신 중앙 정렬된 네이티브 NSPathControl과 입력 필드를 전환한다. 홈 내부는 홈부터, 외부 경로는 루트부터 경로 구성 요소별로 표시한다. 중간 폴더 클릭은 이동, 현재 폴더명/빈 영역 클릭은 경로 편집이다.
- Enter/포커스 이탈로 한 번만 적용, Esc 취소, 물결표·상대 경로 정규화, 존재하지 않는 폴더와 일반 파일 입력 시 기존 위치 유지 테스트를 추가했다. 전체 테스트 89개 통과.
- AppStoreDebug 빌드·서명 검증과 Applications 설치 교체를 완료했다. 설치된 앱에서 합성 Fixtures 경로의 구성 요소와 세로 정렬을 확인했다. 이후 사용자 조작 감지로 추가 UI 입력은 중단했으며, 편집 완료 동작은 자동 테스트 결과와 구분한다.


### 2026-10-24 경로 입력 제거 및 이미지 우클릭 메뉴

- 경로 입력 필드와 빈 영역/현재 폴더 더블클릭 편집을 제거했다. 중앙 정렬된 읽기 전용 NSPathControl과 구성 요소별 폴더 이동은 유지한다. 이전 경로 입력 검증은 읽기 전용 구성 검증으로 교체했다.
- 화면3 메뉴: 원본 해상도·방향을 적용한 이미지 복사(⌘C), 절대 경로 텍스트 복사, 연결 앱 목록 및 다른 앱 선택. NSWorkspace로 파일을 열며 기본 앱 연결은 변경하지 않는다. 이미지가 없으면 메뉴를 제공하지 않는다. 화면2 파일 복사 및 텍스트 필드 복사는 유지한다.
- Core 21개 + AppKit 68개 = 89개 테스트 통과. 이미지 클립보드의 픽셀 크기, 파일 URL 부재, 경로 텍스트와 메뉴를 검증했다. 외부 앱을 실제 실행하는 종단 검증은 하지 않았다.
- AppStoreDebug 빌드 및 strict 서명 검증 성공. 이전 설치본 백업 후 /Applications/Mr. Still.app 교체 완료. 로그: /tmp/mr-still-context-tests-final.log, /tmp/mr-still-context-build.log.


### 2026-10-24 100% 배율의 창 크기 변경 시 픽셀 왜곡

- 원본 612×1061 이미지에서 중앙 정렬 좌표가 소수 backing 픽셀에 놓이는 경로를 재현했다. 기존 회귀 실행은 좌표 정렬/레이어 배치 검사 46건에서 실패했다.
- 이미지 그리기 시작점만 backing 픽셀에 맞추고 표시 크기와 배율은 유지한다. 캔버스 레이어는 크기 변경 중 다시 그리며 캐시를 늘이지 않는 중앙 배치를 지정했다. 프레임 위치 변경과 live resize 종료 시에도 다시 그린다.
- 수정 후 같은 재현 테스트 및 전체 90개 테스트(Core 21 + AppKit 69) 통과. AppStoreDebug 빌드와 strict 서명 검증 통과 후 설치본 교체(백업: build/InstallationBackups/20261024-222350).
- 설치된 앱에서 사용자 제공 재현 파일을 열고 100% 상태로 창 너비/높이를 변경했다. 수정 전 일그러졌던 텍스트가 수정 후와 크기 변경 후 모두 선명하게 표시되는 것을 CUA 화면으로 확인했다. 원본 및 금융 정보가 포함된 화면 캡처는 저장소에 추가하지 않았다.
- 로그: /tmp/mr-still-pixel-before.log, /tmp/mr-still-pixel-tests.log, /tmp/mr-still-pixel-build.log.


### 2026-10-24 v1.1.0 공개 배포

- 누적 변경 사항을 v1.1.0 / 빌드 2로 배포한다. 한국어·영어, App Store 별도 구성과 폴더 권한, 홈/경로 탐색, 이미지 우클릭 메뉴와 100% 픽셀 렌더링 수정을 포함한다.
- 일반 Release 구성의 arm64 + x86_64 Universal 앱 및 DMG에 Developer ID 서명과 보안 타임스탬프를 적용했다. Apple 공증은 기존 선택에 따라 생략했다. App Store 제출은 수행하지 않는다.
- 동일 기능 소스의 90개 자동 테스트 통과, Release 빌드·앱/DMG strict 서명 검사·DMG 무결성 검사 완료. 읽기 전용 마운트에서 버전/언어 리소스/Applications 링크를 확인하고 패키지 내부 앱이 빌드 결과물과 파일별로 일치함을 확인했다. Intel 및 macOS 14 실기기 실행은 미검증이다.
- 소스·문서·설정 공개 전 인증 정보와 개인 경로/이미지 포함 여부를 점검했다. DMG와 체크섬은 Releases에만 배포하고 저장소에서는 무시한다.
