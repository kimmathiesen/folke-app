"""who.py mod WHO Child Growth Standards (2006), drenge, median (M) ved 0, 3, 6 og 12 mdr."""
import pytest

import who

# Fra WHO's tabeller (weight/length/head circumference-for-age, boys, months)
MEDIAN_BOYS = {
    "w": {0: 3.3464, 3: 6.3762, 6: 7.9340, 12: 9.6479},
    "l": {0: 49.8842, 3: 61.4292, 6: 67.6236, 12: 75.7488},
    "h": {0: 34.4618, 3: 40.5135, 6: 43.3306, 12: 46.0661},
}
CASES = [(k, m, v) for k, ms in MEDIAN_BOYS.items() for m, v in ms.items()]


@pytest.mark.parametrize("kind,m,median", CASES)
def test_median(kind, m, median):
    assert who.value_at(kind, "boy", m, 0) == pytest.approx(median, abs=1e-4)


@pytest.mark.parametrize("kind,m,median", CASES)
def test_kurve_p50(kind, m, median):
    row = who.curves(kind, "boy", 12)[m]
    assert row["m"] == m
    assert row["p50"] == pytest.approx(median, abs=0.005)


@pytest.mark.parametrize("kind,m,median", CASES)
def test_median_er_50_percentil(kind, m, median):
    assert who.percentile(kind, "boy", m, median) == 50


def test_percentilgraenser_ved_foedsel():
    # WHO: drenge ved fødslen, P3 = 2,5 kg og P97 = 4,3 kg (afrundet)
    row = who.curves("w", "boy", 0)[0]
    assert row["p3"] == pytest.approx(2.5, abs=0.05)
    assert row["p97"] == pytest.approx(4.35, abs=0.05)
    assert row["p3"] < row["p15"] < row["p50"] < row["p85"] < row["p97"]


def test_interpolation_mellem_maaneder():
    mid = who.value_at("w", "boy", 3.5, 0)
    assert MEDIAN_BOYS["w"][3] < mid < who.value_at("w", "boy", 4, 0)


def test_percentil_klemmes_og_uden_for_omraade():
    assert who.percentile("w", "boy", 6, 30) == 99
    assert who.percentile("w", "boy", 6, 3) == 1
    assert who.percentile("w", "boy", 6, None) is None
    assert who.percentile("w", "boy", -1, 5) is None
    assert who.percentile("w", "boy", 25, 12) is None


def test_piger_har_egne_kurver():
    assert who.value_at("w", "girl", 0, 0) < who.value_at("w", "boy", 0, 0)
