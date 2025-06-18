# import os
# import sys
import json
import re

from invoke import run
from natsort import natsorted
from rich.console import Console


def get_running_kernel() -> str:
    command = "uname -r"
    result = run(command, hide=True)
    if result.ok:
        shell_output = result.stdout.splitlines()[-1]

    # trunk-ignore(flake8/W605)
    re_sub_1 = re.compile("\.el7.*")
    # trunk-ignore(flake8/W605)
    re_sub_2 = re.compile("\.el8.*")
    shell_output = re_sub_1.sub("", shell_output)
    shell_output = re_sub_2.sub("", shell_output)

    return shell_output


def get_installed_kernels() -> list:
    command = "ls -1 /boot/"
    result = run(command, hide=True)
    if result.ok:
        shell_output = result.stdout.splitlines()

    kernel_list = []
    re_vmlinuz = re.compile("vmlinuz-")
    # trunk-ignore(flake8/W605)
    re_sub_1 = re.compile("\.el7.*")
    # trunk-ignore(flake8/W605)
    re_sub_2 = re.compile("\.el8.*")
    re_ignore_1 = re.compile(".*0-rescue.*")
    for i in shell_output:
        if re_vmlinuz.match(i) and not re_ignore_1.match(i):
            i = re_vmlinuz.sub("", i)
            i = re_sub_1.sub("", i)
            i = re_sub_2.sub("", i)
            kernel_list.append(i)

    kernel_list = natsorted(kernel_list)
    return kernel_list


def final_json(
    save_file: bool = False,
    file_location: str = "/tmp/syschk_kern.json",
    json_pretty: bool = True,
) -> None:
    console = Console()

    running_kernel = get_running_kernel()
    installed_kernels = get_installed_kernels()
    installed_kernels_oem = []

    re_oem = re.compile(".*-oem.*")
    if re_oem.match(running_kernel):
        for i in installed_kernels:
            if re_oem.match(i):
                installed_kernels_oem.append(i)
        installed_kernels_oem = natsorted(installed_kernels_oem)
        latest_installed_kernel = installed_kernels_oem[-1]
    else:
        latest_installed_kernel = installed_kernels[-1]

    reboot_required = False
    if running_kernel != latest_installed_kernel:
        reboot_required = True

    results = {}
    results["reboot_required"] = reboot_required
    results["running_kernel"] = running_kernel
    results["latest_installed_kernel"] = latest_installed_kernel
    results["list_of_installed_kernels"] = installed_kernels

    json_output_pretty = json.dumps(results, indent=3)
    json_output = json.dumps(results)

    if json_pretty:
        console.print(json_output_pretty)
    else:
        print(json_output)


def final_human(return_result: bool = False) -> None:
    console = Console()

    running_kernel = get_running_kernel()
    installed_kernels = get_installed_kernels()
    installed_kernels_oem = []

    re_oem = re.compile(".*-oem.*")
    if re_oem.match(running_kernel):
        for i in installed_kernels:
            if re_oem.match(i):
                installed_kernels_oem.append(i)
        installed_kernels_oem = natsorted(installed_kernels_oem)
        latest_installed_kernel = installed_kernels_oem[-1]
    else:
        latest_installed_kernel = installed_kernels[-1]

    results = {}
    results["running_kernel"] = running_kernel
    results["latest_installed_kernel"] = latest_installed_kernel
    results["list_of_installed_kernels"] = installed_kernels

    if running_kernel == latest_installed_kernel:
        final_string = (
            "🟢 [royal_blue1]You are running the latest available kernel: [/]"
            + running_kernel
        )
        if return_result:
            return final_string
        else:
            console.print(" " + final_string)
    else:
        final_string = (
            "🔴 [bright_red]Please reboot to apply the kernel update![/]\n        [bright_red]Currently active kernel:[/]     "
            + running_kernel
            + "\n        [green]Latest installed kernel:[/]     "
            + latest_installed_kernel
        )
        if return_result:
            return final_string
        else:
            console.print(" " + final_string)


if __name__ == "__main__":
    final_human()
