# Step Model Workflow

This project now has:

- `train_self_supervised.ps1` for the self-supervised branch
- `train_models.ps1` for the older supervised / pseudo-labeled pipeline

## 1. Collect better logs

Run the app and export IMU logs from the indoor navigation screen.
The CSV now includes:

- `step_source`
- `step_confidence`
- `seconds_since_prev_step`
- `heading_change_since_prev_step`
- `heading_change_rate_since_prev_step`
- `recent_step_interval_mean`
- `recent_step_interval_std`
- `filtered_to_user_accel_ratio`
- `accel_to_gyro_ratio`

If you have manual labels, add a `manual_step_label` or `true_step_label`
column to the CSV. Otherwise the trainer falls back to `imu_step_detected`.

## 2. Train a model

If you want a one-command workflow from the repo root, run:

```powershell
.\train_self_supervised.ps1
```

By default it reads CSV files from `data` and writes:

- `models/self_supervised_step_model.json`

For the older supervised path, run:

```powershell
.\train_models.ps1
```

By default it reads CSV files from `data` and writes:

- `models/step_classifier.json`
- `models/step_length_model.json`

```powershell
py tools\train_step_classifier.py `
  --input-dir "C:\Users\user\Downloads" `
  --output models\step_classifier.json
```

Useful flags:

- `--label-column manual_step_label`
- `--target-specificity 0.8`
- `--epochs 2500`
- `--learning-rate 0.03`

The script splits by log file, trains a weighted logistic classifier, and writes
a fresh `models/step_classifier.json`.

To train the step-length model, use:

```powershell
py tools\train_step_length_model.py `
  --input-dir "C:\Users\user\Downloads" `
  --output models/step_length_model.json
```

## 3. Validate and ship

After generating the model:

```powershell
flutter analyze
.\build_apk.ps1
```

If you want to compare runs, keep the exported CSVs around and retrain with the
same command after collecting more walking sessions.

To train the self-supervised motion model directly, use:

```powershell
py tools\train_self_supervised_step_model.py `
  --input-dir "C:\Users\user\Downloads" `
  --output models\self_supervised_step_model.json
```

To keep the newest logs as validation data instead of training data, exclude
them while training:

```powershell
py tools\train_self_supervised_step_model.py `
  --input-dir data `
  --output models\self_supervised_step_model.json `
  --exclude-glob "imu_log_2026-05-28T22-43*.csv" `
  --exclude-glob "imu_log_2026-05-28T22-44*.csv"
```

Then validate those held-out logs:

```powershell
py tools\validate_self_supervised_step_model.py `
  data\imu_log_2026-05-28T22-44-10.791352.csv `
  data\imu_log_2026-05-28T22-44-17.355230.csv
```
