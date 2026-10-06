# macOS 앱 아이콘

영향: 앱 아이덴티티와 빌드 리소스. docs/spec.md S17. domain-contract의 OFF 상태/기존 메뉴바 동작/비공개 정보/로컬 Git 규칙을 유지합니다.

## Step 1
- 연결 모티프를 직접 SVG 레이어로 디자인하고 Apple Icon Composer .icon 문서에서 유리·조명·그림자 설정. 배경/그림자/유리 효과는 SVG에 굽지 않음.
- Apple의 Xcode 기본 템플릿과 Landmarks 공식 샘플 문서를 구조 참고로 사용하며 샘플 아트워크는 복사하지 않음.
- actool로 Assets.car 및 이전 OS용 icns를 빌드하고 partial Info.plist의 아이콘 메타데이터를 앱에 병합. Xcode 26 이상에서는 실제 layered Assets.car를 생성하며 이전 개발 도구에서는 함께 보관한 icns를 사용. macOS 실행 최소 버전 14는 유지.
- 실패 native 번들 아이콘 검증 → 구현/각 appearance 렌더/시각 확인 → 두 병렬 리뷰 → 필요한 수정/재검증 → 문서/로컬 커밋/기존 설치 앱 업데이트.
- CUA의 Icon Composer 접근 거부를 우회하지 않으며 Apple CLI compile/render를 사용. 제품 앱을 자동 재시작하지 않음.
- [x] 완료

## 실행 규칙
stepped-plan-executor harness mode의 spec-first 검증·병렬 스펙/코드 리뷰·문서 동기화·커밋 규칙을 적용합니다. 기존 로컬 Git/설치 승인을 따릅니다. GitHub/PR/push 없음.
