module genetic.population;

interface Population {

    Population dup();
    void mutate(float coef);
    Population crossWith(Population other, float muationCoef);

    @property double[] values();

    void print();
    @property real mark();
}
