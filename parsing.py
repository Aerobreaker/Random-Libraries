#one-line:
#print('\n{}\n'.format('\n'.join(*(['Duplicate found!\n{}'.format(id) for (id, cnt) in __import__('collections').Counter(tuple(__import__('itertools').compress(line.strip().split(','), cols)) for cols, line in zip(__import__('itertools').repeat([[1 if i+1 in set(s) else 0 for i in range(max(s))] for s in [[int(i) for i in (input('Please input column numbers delimited by comma <1,2>:\n') or '1,2').split(',')]]][0]), open(input('Input file path:\n')))).most_common(num) if cnt > 1] for num in [input('\nShow all duplicates (Yes/<N>o)?\n')[:1].lower()!='y' or None])) or 'No duplicates found.'))

from itertools import compress
seen = set()
shown = set()
showall = input('\nShow all duplicates (Yes/<N>o)?\n')[:1].lower()
columns = input('Input column numbers, delimited by comma <1,2>:\n') or '1,2'
columns = set(int(i) for i in columns.split(','))
columns = [1 if i + 1 in columns else 0 for i in range(max(columns))]
with open(input('Input file path:\n')) as file:
    print()
    for line in file:
        params = line.strip().split(',')
        id = tuple(compress(params, columns))
        if id in seen and id not in shown:
            print('Duplicate found!\n{}'.format(id))
            shown.add(id)
            if showall != 'y':
                break
        seen.add(id)
    if not shown:
        print('No duplicates found.')
    print()


