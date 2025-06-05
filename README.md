# suppconf - Supportconfig Log Filter and Analyzer

`suppconf.sh` is a Bash script designed to streamline the analysis of supportconfig logs. It filters key information from various log files typically found in a supportconfig archive, making it easier to identify issues and perform root cause analysis (RCA).

## Features

- Filters `/var/log/messages` based on specified timeframes or extracts the entire log.
- Extracts specific sections from `boot.txt`, including:
    - `journalctl --no-pager --boot 0` output
    - `/var/log/boot.log` content
    - `dmesg -T` output
- Displays server time and timezone information from `ntp.txt`.
- Attempts to identify the last reboot time from `boot.txt` by analyzing `last -wxF`, `who -b`, `dmesg -T`, and `journalctl` outputs.
- Filters systemd logs for service and unit activity.
- Filters cron logs for job execution details.
- Organizes all filtered logs and analysis results into the `rca_analysis` directory.

## Configuration File (`suppconf.conf`)

`suppconf.sh` uses a configuration file named `suppconf.conf` to define the names of the log files it processes. This file should be in the same directory as the script. If this file is not found, the script will use default filenames.

The format is simple key-value pairs:
```
KEY=value
```

The following keys are recognized:
*   `MESSAGES_FILE`: Path to the messages log file (default: `messages.txt`)
*   `BOOT_FILE`: Path to the boot log file (default: `boot.txt`)
*   `NTP_FILE`: Path to the NTP/timedatectl log file (default: `ntp.txt`)
*   `SYSTEMD_FILE`: Path to the systemd log file (default: `systemd.txt`)
*   `CRON_FILE`: Path to the cron log file (default: `cron.txt`)

Example `suppconf.conf`:
```
MESSAGES_FILE=my_server_messages.log
SYSTEMD_FILE=/var/log/journal_export.txt
CRON_FILE=cron_jobs.log
```
Lines starting with `#` are ignored as comments, as are empty lines. Unknown keys will be ignored with a warning.

## Usage

To use the script, simply execute it with the desired options. If no options are provided, the script will run all available filters and analyses by default.

```bash
./suppconf.sh [options]
```

### Command-line Options

| Option        | Argument          | Description                                                                                                |
|---------------|-------------------|------------------------------------------------------------------------------------------------------------|
| `-messages`   |                   | Filter `/var/log/messages` from `messages.txt`.                                                            |
| `-boot`       | `[type]`          | Filter boot-related logs from `boot.txt`. `[type]` can be: `journal` (default), `log`, `dmesg`, or `all`. |
| `-timeinfo`   |                   | Show server time and timezone information from `ntp.txt`.                                                  |
| `-reboot`     |                   | Scan `boot.txt` for the most recent reboot time.                                                           |
| `-systemd`    |                   | Filters logs from the file specified by `SYSTEMD_FILE` in `suppconf.conf` (default: `systemd.txt`). It looks for messages related to daemon and service startup, shutdown, and failures. |
| `-cron`       |                   | Filters logs from the file specified by `CRON_FILE` in `suppconf.conf` (default: `cron.txt`). It searches for messages related to cron job execution, including commands run and any reported errors. |
| `-from`       | `YYYY-MM-DDTHH:MM`| Specify the start date and time for the messages filter.                                                   |
| `-to`         | `YYYY-MM-DDTHH:MM`| Specify the end date and time for the messages filter.                                                     |
| `-h`, `--help`|                   | Show the help message.                                                                                     |

*If no options are specified, all filters (`-messages`, `-boot all`, `-timeinfo`, `-reboot`, `-systemd`, `-cron`) will be run.*

### Examples

1.  **Run all filters and analyses (default behavior):**
    ```bash
    ./suppconf.sh
    ```

2.  **Filter messages and all boot log types:**
    ```bash
    ./suppconf.sh -messages -boot all
    ```

3.  **Filter messages within a specific timeframe:**
    ```bash
    ./suppconf.sh -messages -from 2023-10-26T10:00 -to 2023-10-26T12:00
    ```

4.  **Only display server time information:**
    ```bash
    ./suppconf.sh -timeinfo
    ```

5.  **Only extract dmesg output from boot logs:**
    ```bash
    ./suppconf.sh -boot dmesg
    ```

6.  **Filter only systemd and cron logs:**
    ```bash
    ./suppconf.sh -systemd -cron
    ```

## Directory Structure

The script will create an `rca_analysis` directory in the current working directory if it doesn't already exist. All output files, including filtered logs and analysis reports, will be saved in this directory.

Example contents of `rca_analysis/`:
- `log-messages.out`
- `journalctl_no_pager.out`
- `var_log_boot.out`
- `dmesg.out`
- `server_time_info.txt`
- `last_reboot.out`
- `systemd_analysis.out`: Contains filtered logs related to systemd units and services.
- `cron_analysis.out`: Contains filtered logs related to cron job activity.

## Dependencies

`suppconf.sh` relies on standard Linux utilities commonly available on most systems, such as `bash`, `sed`, `grep`, `date`, `mkdir`, `cat`, `rm`, `mv`, `cp`, `head`, `echo`, `printf`. It does not have any special external dependencies that need to be installed separately. The input log files (e.g., `messages.txt`, `boot.txt`, `ntp.txt`, `systemd.txt`, `cron.txt`), or the files specified in `suppconf.conf`, are expected to be in the same directory as the script or at the paths specified.

## License

This project is licensed under the MIT License.

Copyright (c) 2025 leviskualo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
