# Bộ nhớ công việc UI — Storm Tracker

Nguồn yêu cầu: [`UI_note.txt`](../UI_note.txt), được người dùng bổ sung ở commit
`c4660a2`. Lộ trình tổng thể vẫn theo [`note1.txt`](../note1.txt).

Người dùng đã yêu cầu tiếp tục triển khai sau lượt ghi nhớ. Mốc MVP bên dưới ghi
những phần đã có; các checkbox gộp trong danh sách chi tiết vẫn để trống nếu chưa
hoàn thành toàn bộ nội dung. Giữ nguyên tệp nguồn để đối chiếu chi tiết.

## Ghi nhận ảnh minh họa

Năm ảnh trong cuộc trò chuyện minh họa một giao diện animation theo dõi mùa bão:

- Bản đồ tối, biển xanh đen, nền lục địa có địa hình; địa danh và lưới tọa độ rõ.
- Biểu tượng nhiều màu đặt tại tâm, lõi có chữ/số, cánh xoáy và quầng sáng.
- Bảng chú giải nổi ở góc trên trái; thẻ hệ thống đang chọn ở góc trên phải.
- Quỹ đạo tô màu theo cường độ, có đoạn nét liền và nét đứt/chấm.
- Dải thống kê phía dưới gồm đồng hồ ngày, tác động, bộ đếm, hoạt động tháng,
  tên mùa/kịch bản, ACE, ENSO và lịch tồn tại từng hệ thống.

Ảnh là **tham chiếu hình thức**, không phải bộ dữ liệu hay yêu cầu sao chép nguyên
xi. Những chữ/số như NOKAEN, ADA, 01W, 91W, năm 2026, $5m, số người chết, ACE và
ENSO trên ảnh không được tự đưa vào dữ liệu thật của TerraFlux. Các tệp ảnh chưa
được lưu trong repo; bản ghi này giữ cách hiểu về chúng, không thay thế ảnh gốc.

## MVP đã triển khai và kiểm chứng

- [x] Schema TOML cho kịch bản được gắn nguồn rõ, ID duy nhất, mốc thời gian tăng,
  loại hệ thống, gió 1 phút/10 m và áp suất tùy chọn; từ chối dữ liệu không hợp lệ.
- [x] Chế độ Storm Tracker riêng, nền đất/đường bờ tối, nhãn địa danh tham chiếu,
  chú giải ngắn, menu hệ thống và bảng thông tin. Đây chưa phải bố cục nổi/dải mùa
  hoàn chỉnh theo ảnh.
- [x] Biểu tượng cánh xoáy, lõi chữ/số và bảng màu đầy đủ L/EX/×/D/SD/S/SS/1–5;
  kích thước đọc trên màn hình, quay định tính theo bán cầu và nút giảm hiệu ứng.
- [x] Chọn bằng chuột/menu, đổi đơn vị gió, quỹ đạo chỉ tới mốc đang xem, màu theo
  cấp đầu đoạn, nét chấm L/nét đứt tàn dư, giữ lịch sử và dấu kết thúc.
- [x] Đồng bộ đồng hồ với thanh phát lại; mở cùng vị trí/thời gian trên trường vật
  lý hoặc địa cầu. Dữ liệu kịch bản không sửa dữ liệu khí quyển; lớp phủ hệ thống trên 2D/3D đã được bổ sung
  trong mốc lớp phủ bên dưới.
- [x] Nguồn kịch bản hiển thị rõ; áp suất thiếu ghi thiếu; không dựng số ACE/ENSO/
  impacts hay suy diễn nhận diện vật lý từ biểu tượng.

Bằng chứng: `test/storms.jl` kiểm tra schema, ngưỡng, đơn vị, nội suy, lịch sử và
đường đổi ngày; `test/tracker_smoke.jl` kiểm tra giao diện, chọn bằng sự kiện chuột,
đồng hồ, chuyển 2D/3D và giữ nguyên dữ liệu mô hình. Các bộ kiểm tra viewer/live
hiện có tiếp tục được dùng để kiểm tra hồi quy.

Còn chờ: xác nhận/phân loại bão nhiệt đới và nâng cấp theo dõi, các nguồn nhập ngoài, bố cục bảng
nổi đầy đủ, nhãn tránh chồng tổng quát, camera bám, chọn đoạn lịch sử, chuyển màu/
mờ tan mượt, sprite animation trực tiếp trên 3D, các thống kê mùa và xuất video. Phần dưới giữ
nguyên toàn bộ yêu cầu chi tiết để không bỏ sót khi hoàn thiện.

## Bổ sung sau phản hồi sử dụng

- [x] Cô lập đầu vào của widget theo chế độ; menu ẩn không nhận chuột/phím và
  popup được đóng khi đổi chế độ. Kiểm tra bằng bấm, gõ tìm kiếm và chọn mục thật
  trong `test/menu_scopes.jl`, cùng hồi quy trên toàn bộ viewer.
- [x] Chỗ tùy biến hình/animation: `assets/storm_tracker/style.toml` và hướng dẫn
  cùng thư mục; hỗ trợ PNG trong suốt/dải PNG ngang nhiều khung, dùng chung hoặc
  riêng từng cấp. Hình procedural dự phòng và logic frame/xoay tách ở
  `src/storm_icons.jl`. Có kiểm tra cấu hình và pixel render của PNG.

## Mốc nhận diện ứng viên mô hình

- [x] Nguồn riêng **Ứng viên từ mô hình** đọc MSLP/u/v của tệp hoặc phiên đang xem;
  tính độ xoáy cầu, cực tiểu áp suất và độ trũng so với vành xung quanh.
- [x] Tiêu chí thử nghiệm công khai, loại dữ liệu thiếu/nền phẳng/xoáy nghịch;
  ký hiệu `L?` / `MODEL_LOW`, gió tầng sigma được ghi khác gió chuẩn bề mặt.
- [x] ID tiền tố ổn định, nối cặp gần nhất với giới hạn tốc độ/thời gian, không
  bù mốc mất tín hiệu, không để lộ ID trước thời điểm sinh. Mất tiêu chí không
  được diễn giải là tan bão; hết tệp không tự đánh dấu track đã tan.
- [x] Tách hoàn toàn khỏi DEMO, nạp lại khi dữ liệu đổi, có trạng thái chờ/rỗng/lỗi,
  mở cùng ô/thời gian trên 2D/3D và không sửa dữ liệu khí quyển.

Bằng chứng và giới hạn: `docs/MODEL_DETECTION.md`, `test/detection.jl`,
`test/detection_viewer.jl`. Đây **chưa phải bộ nhận diện bão nhiệt đới đã kiểm định**;
chưa có xác nhận lõi ấm/hoàn lưu kín, xử lý tách/hợp nhất hoặc đánh giá bằng quan trắc.

## Sau ảnh bản đồ nhiều L? và quỹ đạo chồng nhau

- [x] Dùng nhiệt độ theo tầng để tách dấu hiệu lõi ấm/lạnh/hỗn hợp/thiếu dữ liệu;
  bỏ gradient nền tuyến tính, có chuẩn số ô/tầng và ngưỡng thử nghiệm công khai.
- [x] Thẻ có hai dị thường nhiệt và bằng chứng gió tiếp tuyến bốn phía; không
  coi vĩ độ/cực đại gió hay dấu hiệu lõi ấm là đủ để xác nhận TC hoặc SSHWS.
- [x] Model dùng chấm nhỏ W/C/L?, không vẽ mọi áp thấp như icon bão đang xoay.
  Mặc định chỉ tên/quỹ đạo của tâm đang chọn; bộ lọc nhóm và lịch sử rõ ràng.
- [x] Danh sách mặc định chỉ các tâm đang hoạt động, tự chọn lại khi mất dấu;
  chế độ lịch sử vẫn xem được các ID đã sinh mà không lộ tương lai.

Bằng chứng: `test/structure.jl` (trường xoáy/nhiệt biết trước, dữ liệu thiếu,
gradient nền, bán cầu/đường đổi ngày), `test/detection_viewer.jl` (khung cuối
NetCDF, lọc nhóm, click chấm, lựa chọn, một nhãn/quỹ đạo mặc định và menu ẩn).
Chi tiết phương pháp/giới hạn và ảnh trước khi xuất bản: `docs/MODEL_DETECTION.md`.
Chưa hoàn thành xác nhận TC/EX, đối lưu, gió chuẩn hoặc kiểm định quan trắc.

## Màu khí tượng, hạt gió và bộ dữ liệu dài hơn

- [x] Bảng màu/thang cố định cho °C, km/h, RH%, MSLP hPa theo phong cách ảnh Zoom
  Earth mới; menu thang dữ liệu, mượt màu 2D, vùng xem và đẳng áp 4 hPa có nhãn.
- [x] Hạt gió có vệt nhạt dần trên 2D/3D, lấy u/v đúng nguồn/tầng/mốc, nội suy
  song tuyến tính và tích phân midpoint theo metric cầu; ngắt vệt khi thiếu dữ
  liệu/đổi mốc/qua đường đổi ngày. Đây là dòng trên snapshot, chưa phải quỹ đạo
  khối khí theo chuỗi thời gian vật lý. Storm Tracker giữ lớp hiển thị riêng.
- [x] RH tính bằng q/T/áp suất bề mặt thật tại tầng sigma; không dùng MSLP hoặc
  đổi độ ẩm riêng thành %. Thiếu áp suất thì ghi thiếu. Live lưu thêm pres.
- [x] Tính sẵn thí nghiệm 60 ngày, 241 mốc 6 giờ, có manifest/cấu hình/restart;
  mặc định mở bộ mới. Live chọn 10/30/60 ngày khi tạo phiên, không đổi phiên cũ.
- [x] Điểm tùy chỉnh màu/range/số hạt/vệt/tốc độ ở `assets/weather/style.toml`.

Ảnh và video thật từ app, công thức/giới hạn/cách tái tạo: `docs/WEATHER_MAPS.md`.
Bằng chứng: `test/weather_data.jl`, `test/weather_viewer.jl`, hồi quy viewer/
tracker và `test/live_viewer_smoke.jl` với hai đoạn mô phỏng thật. Tham chiếu mới
chỉ dùng phong cách màu/lớp dữ liệu; không nhập số, track, forecast cone hay logo
Zoom Earth vào thí nghiệm. Lưới T32 không được ghi thành ICON/GFS 13–22 km.

## Lớp phủ, bán kính, địa cầu mượt và bộ tạo phiên

- [x] Cỡ icon tương đối theo vùng gió xoáy quanh tâm; bán kính có kiểm tra
  bốn phía/thiếu dữ liệu/cận dưới, không suy từ max gió hoặc coi là R34.
- [x] Lớp phủ hệ thống độc lập trên trường vật lý 2D/3D, chọn nguồn mô hình hoặc
  kịch bản; tên/giá trị địa danh, ngày đêm theo UTC mô hình và lưới tọa độ.
- [x] Popup theo trường/tầng/mốc ở con trỏ; thêm ID/nguồn/bán kính khi có vùng
  xoáy, vòng địa lý và lịch sử khi hover; không tạo cone dự báo không có dữ liệu.
- [x] Nội suy màu trên mesh cầu dùng chung đỉnh, làm mịn đường bờ/kinh vĩ tuyến,
  giữ đọc số từ ô gốc, nối kín đường đổi ngày và xử lý cực.
- [x] Create_Simulation.bat/.sh mở form chọn ngày/T/tầng/chu kỳ lưu/CPU/seed,
  worker riêng, cấu hình/nhật ký/manifest và mở kết quả đã kiểm chứng.
- [x] Nhật ký khởi động/worker, nút mở log, tiến độ theo đồng hồ mô hình và ETA;
  phân biệt 100% tích phân với kiểm chứng, lỗi nạp thư viện/cấu hình được ghi
  đúng trạng thái trên Julia 1.13, giữ kết quả khi đóng form ngay sau hoàn tất.
- [x] Ghi rõ GPU dựng hình qua OpenGL, physics CPU; CUDA upstream có hỗ trợ nhưng
  project chưa tích hợp/kiểm chứng trên GPU thật.

Hướng dẫn và giới hạn: [MAP_OVERLAYS.md](MAP_OVERLAYS.md),
[LOCAL_SIMULATION.md](LOCAL_SIMULATION.md), [GPU_STATUS.md](GPU_STATUS.md).
Kiểm chứng bằng extents/overlays_math/overlays_viewer/setup_viewer và
batch_status/batch_worker_errors/model_progress; đã tính thật
T63/16 tầng/1 ngày/6 giờ và từ form T21/8 tầng/1 ngày/24 giờ. Chưa có cone dự báo,
phân loại TC kiểm định, tránh chồng mọi nhãn hoặc tích hợp CUDA của project.

## V2 đầu tiên — can thiệp nhiệt lên phiên live

- [x] Bảng Can thiệp nhiệt riêng, chọn tâm từ bản đồ/địa cầu, tầng sigma, bán
  kính và ΔT, vòng xem trước; cô lập input với trường vật lý/overlay/Tracker.
- [x] Một lần trên một tầng của mô hình thật khi đã tạm dừng và xem mốc cuối;
  kiểm tra đầu vào, chiếu phổ, không sửa dữ liệu mẫu hoặc tự chạy thời gian.
- [x] Checkpoint trước/sau gồm biến, đồng hồ và RNG task worker; nhật ký tác
  động/hoàn tác/từ chối, ước lượng nhiệt lượng khô bằng trọng số native.
- [x] Hoàn tác một cấp trước bước tính mới; khung cũ giữ trạng thái trước tác
  động, mốc sau +6 giờ phản ánh tiến triển vật lý.

Phương pháp/cách dùng/giới hạn: [THERMAL_EXPERIMENTS.md](THERMAL_EXPERIMENTS.md).
Bằng chứng: thermal_patch/thermal_model/intervention_viewer. Chưa phải toàn bộ
V2: can thiệp ẩm/gió/tạo xoáy, tác động tăng dần/duy trì, khôi phục phiên sau
khi đóng app và so sánh A/B vẫn còn chờ.

## Danh sách cần làm theo tài liệu nguồn

### Đối chiếu phân loại Mỹ

- [x] Đã đọc nguồn NOAA/NWS tiếng Anh, ghi định nghĩa/đặc điểm và liên kết trong
  `STORM_CLASSIFICATION_US.txt`; tập trung quy tắc ở `src/classification.jl`.
- [x] Tách loại hệ thống, chuẩn gió và basin; WPAC TY/STY (64/130 kt), hurricane/
  major hurricane, Category tương đương và không đồng nhất STY với C5 (137 kt).
- [x] Bổ sung low/posttropical; remnant <34 kt; cận nhiệt không tự thành typhoon;
  thiếu chuẩn gió trả UNKNOWN. Mô hình thiếu xác nhận cấu trúc/gió chuẩn giữ L?.
- [x] Thẻ/chú giải dùng quy tắc Mỹ; kiểm tra biên, chuẩn gió, chuyển loại, schema
  và phân loại không đổi khi đổi góc nhìn trong `test/classification.jl` và
  `test/tracker_smoke.jl`.
- [ ] Bổ sung và kiểm định chẩn đoán cấu trúc/gió chuẩn để xác nhận TC từ mô hình.

### A. Chế độ và ngôn ngữ hình ảnh — mục 1, 2, 14

- [ ] Thêm chế độ riêng có tên gợi ý **Storm Tracker**; bản đồ chiếm phần lớn màn
  hình, bảng nổi và dải thống kê có thể thu gọn.
- [ ] Dùng chung dữ liệu/thời gian với trường vật lý và địa cầu 3D; chuyển chế độ
  không thay đổi trạng thái mô phỏng.
- [ ] Nền tối, chữ trắng, tên hệ thống đậm có viền/bóng; bảng đen bán trong suốt,
  viền theo màu hệ thống, đầu vát/hình thang; đồng hồ/bộ đếm tròn.
- [ ] Thống nhất màu biểu tượng, chú giải, quỹ đạo; glow nhẹ, chuyển màu/trạng thái
  mượt; có tùy chọn giảm hiệu ứng.

### B. Bản đồ — mục 3

- [ ] Nền địa hình/ảnh vệ tinh, đường bờ, ranh giới phù hợp và nhãn địa danh.
- [ ] Lưới chính/phụ khác độ đậm, nhãn kinh/vĩ độ lớn dễ đọc.
- [ ] Vùng theo dõi/trách nhiệm bằng nét đứt và nhãn dọc/nghiêng; bật/tắt độc lập.
- [ ] Chọn khu vực/đại dương, đổi phép chiếu, pan/zoom, bám camera theo hệ thống.
- [ ] Bật/tắt địa danh, lưới, ranh giới; mở cùng hệ thống trên địa cầu 3D hoặc các
  trường gió/áp suất/nhiệt độ/ẩm/mây khi trường đó có dữ liệu.

### C. Biểu tượng, phân loại và chú giải — mục 4, 5

- [ ] Lõi chữ/số và các vòng/cung/cánh xoáy; xoay, di chuyển, đổi màu/hình dạng
  khi chuyển loại/cường độ; mờ dần khi tan, giữ lịch sử nếu bật.
- [ ] Bảng chú giải góc trên trái có tiêu đề/logo, từng hàng gồm biểu tượng,
  tên, mô tả/ngưỡng gió và viền/nền tương ứng; thu gọn/chuyển nhóm được.
- [ ] Lập bảng biểu diễn theo quy tắc trong nguồn:

| Loại | Ký hiệu | Màu tham chiếu |
| --- | --- | --- |
| Tropical Disturbance | L | Cyan |
| Extratropical Cyclone | EX | Xám |
| Remnant Low | × | Xám |
| Tropical Depression | D | Xanh dương |
| Subtropical Depression | SD | Tím |
| Tropical Storm | S | Xanh lá sáng |
| Subtropical Storm | SS | Xanh lá nhạt |
| Category 1–5 | 1–5 | Vàng sáng, vàng cam, cam, đỏ, hồng/magenta |

- [ ] Khai báo hệ phân loại, ngưỡng, chuẩn/thời gian lấy trung bình gió và cách gọi
  cấp; hỗ trợ m/s, km/h, knot, mph. Các khoảng mph trong ảnh được chép trong mục
  5.3 của `UI_note.txt`; không dùng các khoảng nguyên đó như ranh giới số thực
  nếu chưa định nghĩa chính xác, và không trộn thang phân loại.
- [ ] Kích thước biểu tượng phục vụ đọc bản đồ; không coi là bán kính bão. Phạm
  vi gió/ảnh hưởng là lớp riêng nếu có dữ liệu. Chiều quay phù hợp bán cầu/trạng
  thái; tốc độ animation không mặc nhiên là tốc độ gió.

### D. Nhãn, chọn hệ thống và thẻ chi tiết — mục 6, 8, 12

- [ ] Mã, tên quốc tế/địa phương, INVEST/trạng thái; xử lý nhãn chồng nhau,
  ưu tiên hệ thống đang chọn, giảm nhãn phụ và có danh sách chọn hệ thống.
- [ ] Bấm biểu tượng mở thẻ; hover xem nhanh; chuyển giữa hệ thống, lọc nhóm,
  chỉnh kích thước biểu tượng/nhãn; bám camera theo tâm.
- [ ] Thẻ góc trên phải: biểu tượng, cấp/loại, tên và các mục có dữ liệu như
  damages, deaths, ACE hệ thống; cách trình bày theo ảnh tham chiếu.
- [ ] Các phần bổ sung được tài liệu gợi ý: gió cực đại, áp suất tâm, vị trí,
  hướng/tốc độ di chuyển, thời gian tồn tại, nút bám tâm và biểu đồ diễn biến.

### E. Quỹ đạo và thời gian — mục 7, 12

- [ ] Đường đi tô màu theo cấp tại từng thời điểm; quy ước nét liền/đứt/chấm
  có chú giải; giữ đường và dấu kết thúc sau khi tan.
- [ ] Bật/tắt từng quỹ đạo/toàn mùa; bấm một đoạn để xem trạng thái quá khứ.
- [ ] Nếu thêm dự báo: tách khỏi lịch sử đã mô phỏng, ghi thời điểm phát hành
  và ý nghĩa đường dự báo; chưa mặc định phải có dự báo.
- [ ] Liên kết chạy/tạm dừng, tiến khoảng thời gian, tốc độ phát lại và tua tới
  mốc đã lưu; giữ phân biệt tính mô hình với phát lại hình ảnh.
- [ ] Chụp ảnh/xuất video không kèm nút điều khiển.

### F. Dải thống kê mùa — mục 9

- [ ] Đồng hồ ngày/tháng và cung thời gian; nhãn năm, khu vực, kịch bản, tên thí nghiệm.
- [ ] IMPACTS: tổng damages/fatalities có nguồn dữ liệu.
- [ ] Bộ đếm TS, C1+, C3+; giải thích các nhóm bao hàm nhau; chỉ tính chênh lệch
  tham chiếu khi có nguồn thích hợp.
- [ ] MONTHLY ACTIVITY theo JAN–DEC, màu nhóm thống nhất; tháng chưa diễn ra
  để trống/giảm sáng.
- [ ] Đồng hồ ACE mùa và ACE TIMELINE tích lũy; mùa hiện tại cyan, tham chiếu
  vàng. Chỉ vẽ trung bình 1991–2020 khi có dữ liệu phù hợp.
- [ ] ENSO: giá trị bất thường °C, trạng thái và màu; ghi rõ tính từ mô hình,
  nhập ngoài hay tham số kịch bản.
- [ ] SEASON TIMELINE: mỗi hệ thống một thanh tồn tại, từng đoạn màu cường độ;
  chọn thanh để mở hệ thống hoặc chuyển thời điểm.

### G. Tác động, thông báo và nguồn dữ liệu — mục 10, 11, 13

- [ ] Nhãn tác động trên bản đồ có chú giải damages/deaths, bật/tắt riêng,
  xuất hiện ngắn hạn rồi mờ để không che dữ liệu.
- [ ] Thiệt hại/thương vong phải từ mô hình tác động riêng, dữ liệu ngoài hoặc
  kịch bản được gắn nhãn; **không suy ra chỉ từ cấp bão**.
- [ ] Vùng thông báo/chú thích ngắn và thu gọn được: ký hiệu, chuyển trạng thái,
  kịch bản giả định/không phải dự báo, ý nghĩa so sánh khí hậu tham chiếu.
- [ ] Mỗi hệ thống có ID ổn định. Vị trí/trạng thái từ nhận diện–theo dõi hoặc
  kịch bản được khai báo; không lấy animation làm bằng chứng mô phỏng vật lý.
- [ ] Trường chưa có dữ liệu hiển thị **chưa có dữ liệu** hoặc ẩn; không điền
  số trang trí như thể đó là kết quả mô hình.

## Phụ thuộc cần giải quyết trước khi coi là kết quả vật lý

- Hiện bộ mẫu TerraFlux là T32/8 tầng, bộ tạo phiên chọn T21–T85, xem 2D/3D, chạy phiên mới và
  Storm Tracker có kịch bản và ứng viên từ dữ liệu mô hình; chưa xác nhận/phân loại
  bão nhiệt đới và chưa có mô hình tác động.
- Cần định nghĩa schema hệ thống + mẫu trạng thái theo thời gian + provenance
  (nhận diện mô hình / nhập ngoài / kịch bản), ID, quy tắc liên kết quỹ đạo.
- Cần xác định gió dùng phân loại là đại lượng nào, tại tầng/độ cao nào và lấy
  trung bình bao lâu. Không mặc nhiên xem cực đại gió một ô/tầng ở lưới T32 là
  gió duy trì bề mặt theo chuẩn SSHWS.
- ACE cần quy tắc, đơn vị, chuẩn gió và lấy mẫu phù hợp trước khi cộng; ENSO cần
  định nghĩa vùng/chỉ số/chuẩn khí hậu hoặc nguồn kịch bản. Nguồn chưa có thì ẩn.

## Thứ tự triển khai gợi ý, chưa phải quyết định mới của người dùng

1. Schema/provenance và khung Storm Tracker; có thể dùng kịch bản thử được gắn
   nhãn để kiểm tra UI, giữ tách biệt với kết quả mô hình.
2. Biểu tượng, chú giải, nhãn, chọn hệ thống, quỹ đạo và đồng bộ thời gian/2D/3D.
3. Nhận diện–theo dõi từ trường vật lý, đánh giá giới hạn T32 và chuẩn phân loại.
4. Thẻ chi tiết/dải thống kê, bổ sung từng chỉ số khi có nguồn và quy tắc hợp lệ.
5. Hoàn thiện animation, bản đồ nền/nhãn, giảm hiệu ứng, chụp ảnh/xuất video.

Khi hoàn thành một mục, đánh dấu cùng bằng chứng kiểm tra và cập nhật phần còn
thiếu. Không đánh dấu hoàn thành chỉ vì đã vẽ được một biểu tượng hoặc bảng số.
