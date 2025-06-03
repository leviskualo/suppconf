# rca - Supportconfig Log Filter and Analyzer

`rca` is a Bash script designed to streamline the analysis of supportconfig logs. It filters key information from various log files typically found in a supportconfig archive, making it easier to identify issues and perform root cause analysis (RCA).

## Features

- Filters `/var/log/messages` based on specified timeframes or extracts the entire log.
- Extracts specific sections from `boot.txt`, including:
    - `journalctl --no-pager --boot 0` output
    - `/var/log/boot.log` content
    - `dmesg -T` output
- Displays server time and timezone information from `ntp.txt`.
- Attempts to identify the last reboot time from `boot.txt` by analyzing `last -wxF`, `who -b`, `dmesg -T`, and `journalctl` outputs.
- Organizes all filtered logs and analysis results into the `rca_analysis` directory.

## Usage

To use the script, simply execute it with the desired options. If no options are provided, the script will run all available filters and analyses by default.

```bash
./rca [options]
```

### Command-line Options

| Option        | Argument          | Description                                                                                                |
|---------------|-------------------|------------------------------------------------------------------------------------------------------------|
| `-messages`   |                   | Filter `/var/log/messages` from `messages.txt`.                                                            |
| `-boot`       | `[type]`          | Filter boot-related logs from `boot.txt`. `[type]` can be: `journal` (default), `log`, `dmesg`, or `all`. |
| `-timeinfo`   |                   | Show server time and timezone information from `ntp.txt`.                                                  |
| `-reboot`     |                   | Scan `boot.txt` for the most recent reboot time.                                                           |
| `-from`       | `YYYY-MM-DDTHH:MM`| Specify the start date and time for the messages filter.                                                   |
| `-to`         | `YYYY-MM-DDTHH:MM`| Specify the end date and time for the messages filter.                                                     |
| `-h`, `--help`|                   | Show the help message.                                                                                     |

### Examples

1.  **Run all filters and analyses (default behavior):**
    ```bash
    ./rca
    ```

2.  **Filter messages and all boot log types:**
    ```bash
    ./rca -messages -boot all
    ```

3.  **Filter messages within a specific timeframe:**
    ```bash
    ./rca -messages -from 2023-10-26T10:00 -to 2023-10-26T12:00
    ```

4.  **Only display server time information:**
    ```bash
    ./rca -timeinfo
    ```

5.  **Only extract dmesg output from boot logs:**
    ```bash
    ./rca -boot dmesg
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

## Dependencies

`rca` relies on standard Linux utilities commonly available on most systems, such as `sed`, `grep`, `date` etc. It does not have any special external dependencies that need to be installed separately. 
