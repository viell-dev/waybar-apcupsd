#!/usr/bin/env python3

import json
import os
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_DIR = Path(__file__).resolve().parent.parent
MODULE = REPO_DIR / "ups-status.sh"


def build_status_output(
    *,
    status="ONLINE",
    bcharge="100.0 Percent",
    loadpct="12.0 Percent",
    timeleft="45.0 Minutes",
    linev="230.0 Volts",
):
    return textwrap.dedent(
        f"""\
        STATUS   : {status}
        BCHARGE  : {bcharge}
        LOADPCT  : {loadpct}
        TIMELEFT : {timeleft}
        LINEV    : {linev}
        """
    )


class UpsStatusTestCase(unittest.TestCase):
    maxDiff = None

    def run_module(
        self,
        *,
        apcaccess_output=None,
        apcaccess_exit_code=0,
        apcaccess_stderr=None,
        extra_env=None,
        capture_debug_log=False,
    ):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            mock_apcaccess = temp_path / "apcaccess"
            mock_output = temp_path / "apcaccess-status.txt"
            mock_error = temp_path / "apcaccess-stderr.txt"
            debug_log = temp_path / "debug.log"
            payload = apcaccess_output or ""
            mock_output.write_text(payload)
            mock_error.write_text(apcaccess_stderr or "")

            mock_apcaccess.write_text(
                textwrap.dedent(
                    f"""\
                    #!/usr/bin/env bash
                    set -euo pipefail

                    if [[ "$#" -ne 0 ]]; then
                        exit 1
                    fi

                    if [[ "{apcaccess_exit_code}" -ne 0 ]]; then
                        cat "{mock_error}" >&2
                        exit "{apcaccess_exit_code}"
                    fi

                    cat "{mock_output}"
                    """
                )
            )
            mock_apcaccess.chmod(mock_apcaccess.stat().st_mode | stat.S_IEXEC)

            env = os.environ.copy()
            env["PATH"] = f"{temp_dir}:{env['PATH']}"
            if capture_debug_log:
                env["DEBUG_LOG"] = str(debug_log)
            if extra_env:
                env.update(extra_env)

            result = subprocess.run(
                [str(MODULE)],
                cwd=REPO_DIR,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )

            self.assertEqual(result.stderr, "")
            data = json.loads(result.stdout)
            debug_output = debug_log.read_text() if debug_log.exists() else ""

        if capture_debug_log:
            return data, debug_output
        return data

    def assert_status(
        self,
        *,
        status_output,
        expected_class,
        expected_alt,
        expected_text,
        tooltip_contains=(),
        extra_env=None,
    ):
        data = self.run_module(apcaccess_output=status_output, extra_env=extra_env)

        self.assertEqual(data["class"], expected_class)
        self.assertEqual(data["alt"], expected_alt)
        self.assertEqual(data["text"], expected_text)

        for fragment in tooltip_contains:
            self.assertIn(fragment, data["tooltip"])

    def test_online(self):
        self.assert_status(
            status_output=build_status_output(status="ONLINE"),
            expected_class="online",
            expected_alt="charging",
            expected_text="100%",
        )

    def test_on_battery_above_warning_threshold(self):
        self.assert_status(
            status_output=build_status_output(status="ONBATT", bcharge="80.0 Percent"),
            expected_class="on-battery",
            expected_alt="discharging",
            expected_text="80%",
        )

    def test_on_battery_above_default_warning_threshold(self):
        self.assert_status(
            status_output=build_status_output(status="ONBATT", bcharge="45.0 Percent"),
            expected_class="on-battery",
            expected_alt="discharging",
            expected_text="45%",
        )

    def test_on_battery_default_warning_threshold(self):
        self.assert_status(
            status_output=build_status_output(status="ONBATT", bcharge="15.0 Percent"),
            expected_class="warning",
            expected_alt="discharging",
            expected_text="15%",
            tooltip_contains=("Battery charge at or below warning threshold",),
        )

    def test_on_battery_missing_charge_does_not_trigger_charge_threshold(self):
        self.assert_status(
            status_output=build_status_output(status="ONBATT", bcharge=""),
            expected_class="on-battery",
            expected_alt="discharging",
            expected_text="Unknown",
            tooltip_contains=("Battery charge unavailable.", "Battery: unavailable"),
        )

    def test_on_battery_invalid_charge_does_not_trigger_charge_threshold(self):
        self.assert_status(
            status_output=build_status_output(status="ONBATT", bcharge="N/A"),
            expected_class="on-battery",
            expected_alt="discharging",
            expected_text="Unknown",
            tooltip_contains=("Battery charge unavailable.", "Battery: N/A"),
        )

    def test_on_battery_charge_above_100_is_clamped_to_full(self):
        self.assert_status(
            status_output=build_status_output(status="ONBATT", bcharge="101.0 Percent"),
            expected_class="on-battery",
            expected_alt="discharging",
            expected_text="100%",
            tooltip_contains=("Battery: 100%"),
        )

    def test_on_battery_negative_charge_is_clamped_to_empty(self):
        self.assert_status(
            status_output=build_status_output(status="ONBATT", bcharge="-1.0 Percent"),
            expected_class="warning",
            expected_alt="discharging",
            expected_text="0%",
            tooltip_contains=("Battery charge at or below warning threshold", "Battery: 0%"),
        )

    def test_on_battery_configurable_warning_threshold(self):
        self.assert_status(
            status_output=build_status_output(status="ONBATT", bcharge="45.0 Percent"),
            expected_class="warning",
            expected_alt="discharging",
            expected_text="45%",
            tooltip_contains=("Battery charge at or below warning threshold",),
            extra_env={"WARNING_CHARGE": "50"},
        )

    def test_on_battery_configurable_critical_threshold(self):
        self.assert_status(
            status_output=build_status_output(status="ONBATT", bcharge="45.0 Percent"),
            expected_class="critical",
            expected_alt="discharging",
            expected_text="45%",
            tooltip_contains=("Battery charge at or below critical threshold",),
            extra_env={"WARNING_CHARGE": "0", "CRITICAL_CHARGE": "50"},
        )

    def test_on_battery_lowbatt_is_shutdown_imminent(self):
        self.assert_status(
            status_output=build_status_output(status="ONBATT LOWBATT", bcharge="15.0 Percent"),
            expected_class="critical",
            expected_alt="discharging",
            expected_text="15%",
            tooltip_contains=("LOW BATTERY - Shutdown imminent",),
        )

    def test_online_lowbatt_is_warning_with_charging_icon(self):
        self.assert_status(
            status_output=build_status_output(status="ONLINE LOWBATT", bcharge="15.0 Percent"),
            expected_class="warning",
            expected_alt="charging",
            expected_text="15%",
            tooltip_contains=("Battery low, currently on mains power",),
        )

    def test_online_overload_keeps_power_icon(self):
        self.assert_status(
            status_output=build_status_output(status="ONLINE OVERLOAD", bcharge="88.0 Percent"),
            expected_class="warning",
            expected_alt="charging",
            expected_text="88%",
            tooltip_contains=("UPS OVERLOADED",),
        )

    def test_online_replacebatt_is_warning(self):
        self.assert_status(
            status_output=build_status_output(status="ONLINE REPLACEBATT", bcharge="88.0 Percent"),
            expected_class="warning",
            expected_alt="charging",
            expected_text="88%",
            tooltip_contains=("REPLACE BATTERY",),
        )

    def test_shutting_down_uses_alert_icon(self):
        self.assert_status(
            status_output=build_status_output(status="SHUTTING DOWN", bcharge="25.0 Percent"),
            expected_class="critical",
            expected_alt="alert",
            expected_text="Alert",
            tooltip_contains=("SHUTTING DOWN",),
        )

    def test_commlost_uses_unknown_icon(self):
        self.assert_status(
            status_output=build_status_output(status="COMMLOST", bcharge="0.0 Percent"),
            expected_class="warning",
            expected_alt="unknown",
            expected_text="Unknown",
            tooltip_contains=("COMMUNICATION LOST",),
        )

    def test_online_commlost_prefers_unknown_icon(self):
        self.assert_status(
            status_output=build_status_output(status="ONLINE COMMLOST", bcharge="54.0 Percent"),
            expected_class="warning",
            expected_alt="unknown",
            expected_text="Unknown",
            tooltip_contains=("COMMUNICATION LOST",),
        )

    def test_no_battery_is_critical_alert(self):
        self.assert_status(
            status_output=build_status_output(status="NOBATT", bcharge="0.0 Percent"),
            expected_class="critical",
            expected_alt="alert",
            expected_text="Alert",
            tooltip_contains=("NO BATTERY DETECTED",),
        )

    def test_lowbatt_without_power_context_is_critical_alert(self):
        self.assert_status(
            status_output=build_status_output(status="LOWBATT", bcharge="4.0 Percent"),
            expected_class="critical",
            expected_alt="alert",
            expected_text="Alert",
            tooltip_contains=("LOW BATTERY - Power state unknown",),
        )

    def test_unknown_status_is_reported(self):
        self.assert_status(
            status_output=build_status_output(status="MYSTERY", bcharge="66.0 Percent"),
            expected_class="warning",
            expected_alt="unknown",
            expected_text="Unknown",
            tooltip_contains=("Unknown status flag(s): MYSTERY",),
        )

    def test_blank_status_field_is_reported_as_unknown_status(self):
        self.assert_status(
            status_output=build_status_output(status="", bcharge="66.0 Percent"),
            expected_class="warning",
            expected_alt="unknown",
            expected_text="Unknown",
            tooltip_contains=("Unknown status: <empty>", "Status: "),
        )

    def test_missing_status_field_returns_critical_payload(self):
        status_output = textwrap.dedent(
            """\
            BCHARGE  : 66.0 Percent
            LOADPCT  : 12.0 Percent
            TIMELEFT : 45.0 Minutes
            LINEV    : 230.0 Volts
            """
        )

        data = self.run_module(apcaccess_output=status_output)

        self.assertEqual(data["text"], "Error")
        self.assertEqual(data["alt"], "alert")
        self.assertEqual(data["class"], "critical")
        self.assertEqual(data["percentage"], 0)
        self.assertIn("missing STATUS field", data["tooltip"])

    def test_status_text_with_json_metacharacters_is_escaped(self):
        status = 'MYSTERY"FLAG\\PATH'

        self.assert_status(
            status_output=build_status_output(status=status, bcharge="66.0 Percent"),
            expected_class="warning",
            expected_alt="unknown",
            expected_text="Unknown",
            tooltip_contains=(f"Unknown status flag(s): {status}", f"Status: {status}"),
        )

    def test_status_text_with_literal_unicode_escape_sequence_is_escaped(self):
        status = r"MYSTERY\u26A0"

        self.assert_status(
            status_output=build_status_output(status=status, bcharge="66.0 Percent"),
            expected_class="warning",
            expected_alt="unknown",
            expected_text="Unknown",
            tooltip_contains=(f"Unknown status flag(s): {status}", f"Status: {status}"),
        )

    def test_status_text_with_multibyte_unicode_is_preserved(self):
        status = "MYSTERY⚠é😀"

        self.assert_status(
            status_output=build_status_output(status=status, bcharge="66.0 Percent"),
            expected_class="warning",
            expected_alt="unknown",
            expected_text="Unknown",
            tooltip_contains=(f"Unknown status flag(s): {status}", f"Status: {status}"),
        )

    def test_status_text_with_control_character_uses_unicode_escape(self):
        status = "MYSTERY\x1fFLAG"

        self.assert_status(
            status_output=build_status_output(status=status, bcharge="66.0 Percent"),
            expected_class="warning",
            expected_alt="unknown",
            expected_text="Unknown",
            tooltip_contains=(f"Unknown status flag(s): {status}", f"Status: {status}"),
        )

    def test_field_values_may_contain_colons(self):
        self.assert_status(
            status_output=build_status_output(status="VENDOR:FLAG", bcharge="66.0 Percent"),
            expected_class="warning",
            expected_alt="unknown",
            expected_text="Unknown",
            tooltip_contains=("Unknown status flag(s): VENDOR:FLAG", "Status: VENDOR:FLAG"),
        )

    def test_status_whitespace_and_padded_charge_are_normalized(self):
        self.assert_status(
            status_output=build_status_output(
                status="  ONLINE   LOWBATT  ",
                bcharge="095.0 Percent",
            ),
            expected_class="warning",
            expected_alt="charging",
            expected_text="95%",
            tooltip_contains=("Battery low, currently on mains power",),
        )

    def test_info_flags_are_listed_in_tooltip(self):
        self.assert_status(
            status_output=build_status_output(status="ONLINE BOOST CAL SLAVEDOWN", bcharge="90.0 Percent"),
            expected_class="online",
            expected_alt="charging",
            expected_text="90%",
            tooltip_contains=(
                "Voltage boost active.",
                "Calibration in progress.",
                "Slave not responding.",
            ),
        )

    def test_apcaccess_failure_returns_critical_payload(self):
        data = self.run_module(
            apcaccess_exit_code=1,
            apcaccess_stderr="Error contacting apcupsd @ localhost:3551: Connection refused\n",
        )

        self.assertEqual(data["text"], "Error")
        self.assertEqual(data["alt"], "alert")
        self.assertEqual(data["class"], "critical")
        self.assertEqual(data["percentage"], 0)
        self.assertIn("UPS: Cannot query apcupsd", data["tooltip"])
        self.assertIn("Error contacting apcupsd", data["tooltip"])

    def test_empty_apcaccess_output_returns_critical_payload(self):
        data = self.run_module(apcaccess_output="")

        self.assertEqual(
            data,
            {
                "text": "Error",
                "alt": "alert",
                "tooltip": "UPS: apcaccess returned no status data",
                "class": "critical",
                "percentage": 0,
            },
        )

    def test_non_numeric_charge_threshold_config_returns_error_payload(self):
        data = self.run_module(
            apcaccess_output=build_status_output(status="ONLINE"),
            extra_env={"WARNING_CHARGE": "soon"},
        )

        self.assertEqual(data["text"], "Error")
        self.assertEqual(data["alt"], "alert")
        self.assertEqual(data["class"], "critical")
        self.assertIn("Invalid charge threshold config", data["tooltip"])

    def test_out_of_range_charge_threshold_config_returns_error_payload(self):
        data = self.run_module(
            apcaccess_output=build_status_output(status="ONLINE"),
            extra_env={"WARNING_CHARGE": "101"},
        )

        self.assertEqual(data["text"], "Error")
        self.assertEqual(data["alt"], "alert")
        self.assertEqual(data["class"], "critical")
        self.assertIn("integers from 0 to 100", data["tooltip"])

    def test_overlapping_charge_threshold_config_returns_error_payload(self):
        data = self.run_module(
            apcaccess_output=build_status_output(status="ONLINE"),
            extra_env={"WARNING_CHARGE": "20", "CRITICAL_CHARGE": "20"},
        )

        self.assertEqual(data["text"], "Error")
        self.assertEqual(data["alt"], "alert")
        self.assertEqual(data["class"], "critical")
        self.assertIn("CRITICAL_CHARGE must be lower than WARNING_CHARGE", data["tooltip"])

    def test_unknown_status_debug_level_two_logs_once(self):
        _, debug_output = self.run_module(
            apcaccess_output=build_status_output(status="MYSTERY", bcharge="66.0 Percent"),
            extra_env={"DEBUG": "2"},
            capture_debug_log=True,
        )

        self.assertEqual(debug_output.count("=== "), 1)


if __name__ == "__main__":
    unittest.main()
