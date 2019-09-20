#one-line:
#print('{}\n'.format(''.join('\nDuplicate found!\n{}'.format(id) for (id, cnt) in __import__('collections').Counter(tuple(__import__('itertools').compress(line.strip().split(','), cols)) for cols, line in zip(__import__('itertools').repeat(tuple(__import__('itertools').chain.from_iterable(__import__('itertools').chain([i[0] for i in zip(__import__('itertools').repeat(0), __import__('itertools').takewhile(lambda x: x < j-1, c))], [1]) for j, c in eval('zip(sorted(int(k) for k in {0}.split(",")), [__import__("itertools").count()]*len({0}.split(",")))'.format(repr(input('Please input column numbers delimited by comma <1,2>:\n') or '1,2')))))), open(input('Input file path:\n')))).most_common(input('Show all duplicates (Yes/<N>o)?\n')[:1].lower()!='y' or None) if cnt > 1) or '\nNo duplicates found.'))

from itertools import compress
seen = set()
shown = set()
columns = input('Input column numbers, delimited by comma <1,2>:\n') or '1,2'
columns = set(int(i) for i in columns.split(','))
columns = [1 if i + 1 in columns else 0 for i in range(max(columns))]
with open(input('Input file path:\n')) as file:
    showall = input('Show all duplicates (Yes/<N>o)?\n')[:1].lower()
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
