module genetic.rate_population;

import std.algorithm;
import std.array;
import std.concurrency;
import std.math;
import std.random;
import std.range;
import std.stdio;
import genetic.population;
import ode;

private void spawnRecalc(shared RatePopulation pop) {
    auto ode = new Ode(pop);
    ode.main_loop();
}

class RatePopulation : Population {

    //k1 = 5.66e15 * exp(-3360/T) * H;
    //k2 = 0; //2e13 * H;
    //k4 = 1e1;
    //k4_1 = 20e2;
    //k4_2 = 5;
    //k5 = 0; //0.01;
    //k6 = 1e13 * CH3;  //1e13*CH3;
    //k7 = 6.13e12 * exp(-18269/T);
    //k8 = 0; //0.5;
    //k9 = 3.5e20 * exp(-31300/(1.98*T));

    //ORIGINAL
    //k1 = 5.2e13 * H * math.exp(-3360/T)
    //k2 = 2e13 * H
    //k4 = 1e12 * math.exp(-352.3/T)
    //k4_1 = _k4 * 10
    //k5 = 4.79e13 * math.exp(-7196.8/T)
    //k6 = 1e13 * CH3
    //k7 = 6.13e13 * math.exp(-18.269/T)
    //k8 = 0.5
    //k9 = 3.5e8 * math.exp(-31.3/(1.98*T))

    private real _mark;
    private float _k1, _k2, _k4, _k4_1, _k4_2, _k5, _k6, _k7, _k8, _k9;

    shared @property float k1() { return _k1; }
    shared @property float k2() { return _k2; }
    shared @property float k4() { return _k4; }
    shared @property float k4_1() { return _k4_1; }
    shared @property float k4_2() { return _k4_2; }
    shared @property float k5() { return _k5; }
    shared @property float k6() { return _k6; }
    shared @property float k7() { return _k7; }
    shared @property float k8() { return _k8; }
    shared @property float k9() { return _k9; }

    private real[Ode.C] total;
    private real[Ode.C][Ode.L] cc;

    Tid childLoop;

    this(float k1, float k2, float k4, float k5, float k6, float k7, float k8, float k9) {
        _k1 = k1;
        _k2 = k2;
        set_k4(k4);
        _k5 = k5;
        _k6 = k6;
        _k7 = k7;
        _k8 = k8;
        _k9 = k9;

        recalcMark();
    }

    override void print() {
        writeln(_k1, " ", _k2, " ", _k4, " ", _k5, " ", _k6, " ", _k7, " ", _k8, " ", _k9);

        writeln("CC = ", cc);
        writeln("YOYO = ", total);
    }

    override Population dup() {
        return new RatePopulation(_k1, _k2, _k4, _k5, _k6, _k7, _k8, _k9);
    }

    private void set_k4(real v) {
        _k4 = v;
        _k4_1 = v * 10;
        _k4_2 = v * 0.1;
    }

    override void mutate(float coef) {
        waitAndReset();

        real l(real x, uint a, uint b) {
            if (coef * 50 - uniform(0, 100) < 0) return x;
            auto y = x * (coef * a * 0.5f - uniform(0, coef * a)) +
                coef * b * 0.5f - uniform(0, coef * b);
            if (y < 0) y = 0;
            return y;
        };

        _k1 = l(_k1, 100, 5000);
        _k2 = l(_k2, 100, 5000);
        set_k4(l(_k4, 100, 5000));
        _k5 = l(_k5, 10, 500);
        _k6 = l(_k6, 10, 500);
        _k7 = l(_k7, 500, 25000);
        _k8 = l(_k8, 10, 50);
        _k9 = l(_k9, 500, 25000);

        recalcMark();
    }

    private void waitAndReset() {
        if (childLoop != Tid.init) {
            //writeln("wait ", values);
            receiveOnly!bool();
            childLoop = Tid.init;
            //writeln("  reset ", values);
        } else {
            //writeln(" ok ", values);
        }
    }

    override @property real mark() {
        waitAndReset();
        return _mark;
    }

    private void recalcMark() {
        childLoop = spawn(&spawnRecalc, cast(shared) this);
    }

    shared void setCC(shared real[Ode.C][Ode.L] cc) {
        this.cc = cc;

        bool fail = false;
        total[] = 0;

        real stars = 0, hydrogen = 0;
        for (int l = 0; l < Ode.L; l++) {

            real cs = 0;
            for (int j = 0; j < Ode.C;j++) {
                if (isNaN(cc[l][j]) || cc[l][j] < 0) fail = true;
                total[j] += cc[l][j];
                cs += cc[l][j];
            }

            if (l == 0 && (abs(1 - cs) > 1e-10)) fail = true;

            stars = cc[l][1] + cc[l][2] * 2 + cc[l][3] + cc[l][7];
            hydrogen = cc[l][0] * 2 + cc[l][1] + cc[l][4] + cc[l][8];
        }

        _mark = 0;
        if (!fail) {

            real sum = stars + hydrogen;
            if (sum != 0) {
                stars /= sum;
                hydrogen /= sum;
            }

            //_mark = total[6];
            for (int l = Ode.L - 1; l >= 0; l--) {
                _mark += cc[l][6] * pow(3, l + 1);
            }

            _mark /= 1.0 + 1000 * abs(stars - 0.12); // около 12% звёздочек на поверхности
        }

        send(ownerTid, true);
    }

    override @property float[] values() {
        return [_k1, _k2, _k4, _k5, _k6, _k7, _k8, _k9];
    }

    override Population crossWith(Population other) {
        auto pairs = zip(values, other.values);
        auto values = map!((xy) {
            return (xy[0] + xy[1]) * 0.5f;
        })(pairs);

        auto child = new RatePopulation(
            values[0], values[1], values[2], values[3], values[4],
            values[5], values[6], values[7]
        );
        child.mutate(0.1);

        return child;
    }

}
