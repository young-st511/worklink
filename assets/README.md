# Worklink 앱 아이콘

집과 사무실의 연결을 두 개의 고리로 표현한 Worklink 자체 벡터 디자인입니다. 전경은 반투명한 흰색과 시안, 배경은 청색으로 두었습니다. 글자 없이 작은 크기에서도 연결 모티프가 보이도록 구성했습니다.

- `Worklink.icon/`: Icon Composer에서 다시 편집할 수 있는 원본 문서입니다. 1024×1024 SVG 레이어 2개와 native glass/specular/translucency 및 dark fill 설정을 담았습니다. 그림자·유리 효과·앱 아이콘 마스크는 SVG에 미리 그리지 않고 Apple 렌더러가 적용합니다.
- `Worklink.icns`: 같은 원본을 Apple ictool·iconutil로 16–1024px 크기로 생성한 이전 macOS/개발 도구용 아이콘입니다.
- `worklink-preview.png`: Apple ictool의 macOS Default appearance 렌더입니다.

`make icon-previews`는 Default/Dark/ClearLight/ClearDark/TintedLight/TintedDark와 16/32/64 point 미리보기를 `.build/icon-previews`에 생성합니다. Xcode 26 이상에 포함된 Icon Composer CLI가 필요합니다. 원본 편집 후 `make app` 및 `python3 scripts/verify-app-icon.py`로 native 레이어와 appearance를 검증합니다. 원본 편집 후 `sh scripts/build-legacy-icon.sh`로 모든 1x/2x 크기의 fallback 파일과 Default 미리보기를 함께 갱신합니다. actool의 작은 icns stub 대신 이 완전한 크기 세트를 앱에 포함합니다.

`WORKLINK_LEGACY_ICON=1 make app`은 함께 보관한 icns로만 빌드합니다. 최신 개발 도구가 없을 때도 같은 디자인의 앱을 빌드할 수 있지만 이 빌드에는 native Liquid Glass 레이어가 없습니다. 일반 `make app`은 compiler가 있을 때 native 레이어를 컴파일합니다.

문서 구조는 Xcode의 macOS Icon Composer 기본 템플릿과 [Apple Landmarks 샘플](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass)을 참고했습니다. 샘플 이미지·SVG·앱 아트워크는 포함하거나 재사용하지 않았습니다. 스키마는 해당 Xcode의 actool과 renderer로 검증합니다.

공식 제작 안내: [Icon Composer](https://developer.apple.com/icon-composer/), [Icon Composer 아이콘 제작](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).
