main()
{
    new sum = 0;
    for (new i = 0; i < 10; i++)
        sum += i;
    new arr[4] = {1, 2, 3, 4};
    new k = arr[2];
    #pragma unused sum
    #pragma unused k
}
