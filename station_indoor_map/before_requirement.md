pip install --upgrade pip setuptools wheel
pip install numpy pandas openpyxl pyproj shapely
pip install pyogrio geopandas
pip install opencv-python

py build_indoor_map.py `
  --station-shp ".\shp_file\station.shp" `
  --entrance-shp ".\shp_file\entrance.shp" `
  --architecture-csv ".\csv_file\서울교통공사_역사건축정보.csv" `
  --depth-csv ".\csv_file\서울교통공사_역사심도정보.csv" `
  --area-csv ".\csv_file\서울교통공사_역사면적정보.csv" `
  --guide-root ".\station_image" `
  --station-name "신설동역" `
  --output-dir ".\indoor_map"