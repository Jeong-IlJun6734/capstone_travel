python .\image_check.py `
  --image ".\7\장승배기.jpg" `     <- 이 부분을 바꾸면 다른 이미지로 선택 가능.

--output 옵션으로 생성되는 이미지의 출력 경로를 지정해줄 수 있음. 안해도 기본으로 /overlay 아래 생성.

숫자키 1~7로 아래의 노드 타입을 선택 가능.
  1 hall
  2 stairs_start
  3 stairs_end
  4 elevator
  5 platform
  6 entrance_connection
  7 information
  8 qr


층 구분도 가능. F를 누른 후 숫자키 1~5로 지층부터 B4까지 선택 가능.
  F + 1 ground
  F + 2 B1
  F + 3 B2
  F + 4 B3
  F + 5 B4

D toggles Delete mode. In Delete mode, left-click a node or edge to remove it.

If the output JSON already exists, image_check.py loads it automatically so you can continue editing previously clicked nodes.
Use --load path\to\annotation.json to load a different file, or --no-load to start empty.
When --load points to a {line}_{station}_clicked.json file, --image can be omitted and the matching image is inferred.
You can also pass the annotation JSON path directly as the first argument.
