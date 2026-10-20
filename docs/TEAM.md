# Đội ngũ & Quy trình — Studio tự vận hành

> Mỗi "thành viên" là một agent chuyên trách, được Trưởng dự án điều phối qua các workflow có kiểm chứng.
> Nguyên tắc: **nghiên cứu → quyết định có ghi chép (ADR) → xây dựng → kiểm chứng tự động → phê bình độc lập → lặp lại.**

## Sơ đồ tổ chức

| Ban | Vai trò | Trách nhiệm chính | Sản phẩm |
|---|---|---|---|
| **Điều hành** | Trưởng dự án (Director) | Tầm nhìn, chốt quyết định, tích hợp, cổng chất lượng cuối | `docs/GDD.md`, ADR, PR |
| **Nghiên cứu** | Engine Researcher | Năng lực Godot 4.7.2 (đọc trực tiếp mã nguồn engine) | `docs/research/01-*` |
| | Mobile UX & Performance | Công thái học một tay, pin, nhiệt, accessibility, store | `docs/research/02-*` |
| | Tooling & Pipeline | Plugin, font, SVG/ThorVG, audio pipeline, test, CI | `docs/research/03-*` |
| | Game Design & Player Psychology | Khoa học "cozy", ART/SRT, SDT, idle math, đạo đức | `docs/research/04-*` |
| | Art Direction | Xu hướng thẩm mỹ & chuyển động 2026–27, rubric QA | `docs/research/05-*` |
| | Audio & Haptics | Âm thanh thư giãn có bằng chứng, công thức tổng hợp | `docs/research/06-*` |
| | Fact-checkers (đối kháng) | Bác bỏ mọi tuyên bố sai/khó kiểm chứng, sửa tại chỗ | "Verification log" mỗi báo cáo |
| | Lead Researcher | Hợp nhất, giải quyết mâu thuẫn, xếp hạng concept | `docs/research/00-SYNTHESIS.md` |
| **Thiết kế** | Game Designer | Vòng lặp lõi, nội dung, cảm xúc mục tiêu | `docs/GDD.md` |
| | Systems / Economy Designer | Đường cong tiến trình idle, offline progress | `docs/GDD.md` §Economy |
| **Kỹ thuật** | Tech Lead / Architect | Kiến trúc, autoload, dữ liệu, save | `docs/ARCHITECTURE.md` |
| | Gameplay Engineer | Hệ thống lõi, idle sim, input | `scripts/` |
| | UI Engineer | Giao diện cảm ứng, safe-area, i18n (vi/en) | `ui/` |
| | Tools & QA Engineer | Test headless (GUT), chụp màn hình Xvfb, CI | `tests/`, `qa/`, `.github/` |
| **Mỹ thuật** | Art Director | Art bible, palette theo giờ trong ngày | `docs/ART_BIBLE.md` |
| | Technical Artist | Shader canvas_item, VFX, ánh sáng, hạt | `shaders/`, `vfx/` |
| | Vector Illustrator | Minh hoạ SVG viết tay | `art/` |
| | Motion Designer | Token chuyển động, tween, spring, idle "thở" | `scripts/motion/` |
| **Âm thanh** | Sound Designer / Composer | Nhạc generative, ambience, SFX tổng hợp bằng code | `audio/`, `tools/audio/` |
| **QA** | Visual QA Panel (3 giám khảo độc lập) | Chấm điểm ảnh/video theo rubric 10 tiêu chí | `qa/reports/` |
| | Functional QA | Kiểm thử hồi quy, hiệu năng, edge cases | `tests/` |

## Cổng chất lượng (Quality Gates)

1. **Nghiên cứu**: mọi khẳng định kỹ thuật được đối chiếu với mã nguồn Godot 4.7.2 hoặc nguồn chính thức; trích dẫn khoa học có tác giả/năm/DOI.
2. **Kỹ thuật**: dự án import sạch (0 lỗi script), test headless xanh, chạy được trên renderer mục tiêu.
3. **Thẩm mỹ**: ảnh chụp ở 1080×2400 được 3 giám khảo độc lập chấm theo rubric; chỉ "ship" khi điểm trung bình đạt ngưỡng "ship-worthy 2026–27" ở mọi tiêu chí.
4. **Cảm xúc**: checklist "Design Principles" (không áp lực, không thất bại, không FOMO) đạt 100%.

## Ràng buộc sản xuất

- Không có hoạ sĩ, không tải asset có sẵn: mọi hình ảnh là **SVG viết tay + shader + hạt + chuyển động thủ tục**; mọi âm thanh **tổng hợp bằng Python/numpy**; font **OFL từ npm**.
- Plugin chỉ dùng loại **thuần GDScript** cài qua `git clone`, ghim phiên bản cụ thể.
