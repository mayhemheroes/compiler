gcd(a, b)
{
    while (b != 0)
    {
        new t = b;
        b = a % b;
        a = t;
    }
    return a;
}

main()
{
    new g = gcd(48, 36);
    #pragma unused g
}
