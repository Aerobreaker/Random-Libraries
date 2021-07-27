from heapq import heapify as heapify_min, heappush as heappush_min
from heapq import heappop as heappop_min, _heapify_max as heapify_max
from heapq import _heappop_max as heappop_max, _siftdown_max
from heapq import heapreplace as heapreplace_min
from heapq import _heapreplace_max as heapreplace_max


def heappush_max(heap, item):
    heap.append(item)
    _siftdown_max(heap, 0, len(heap)-1)


def main():
    class Node:
        def __init__(self, val):
            self.val = val
            self.enabled = True
        def __lt__(self, other):
            return self.val < other
        def __gt__(self, other):
            return self.val > other
        def __le__(self, other):
            return self.val <= other
        def __ge__(self, other):
            return self.val >= other
        def __eq__(self, other):
            return self.val == other
        def __ne__(self, other):
            return self.val != other
    _min = None
    _max = None
    _sum = None
    cnt = 0
    inp_s = None
    nums = {}
    cnts = {}
    cnt_heap = []  # max_heap
    inps = []
    bot = []  # max_heap
    top = []  # min_heap
    while inp_s != '':
        if len(top) == 0 and len(bot) == 0:
            median = None
        elif len(top) < len(bot):
            median = bot[0]
        elif len(top) > len(bot):
            median = top[0]
        else:
            median = (bot[0]+top[0]) / 2 if (bot[0]&1 + top[0]&1) & 1 else round((bot[0]+top[0]) / 2)
        if len(cnts) == 0:
            mode = None
        else:
            mode = ', '.join(str(i) for i in cnts[cnt_heap[0].val])
        min_s = str(_min)
        max_s = str(_max)
        sum_s = str(_sum)
        avg_s = str(round(_sum/cnt, 4) if cnt else None)
        med_s = str(median)
        mod_s = str(mode)
        maxlen = max(len(min_s), len(max_s), len(sum_s), len(avg_s), len(med_s))
        print('Current minimum : {:{ln}}   Current maximum : {:{ln}}'.format(min_s, max_s, ln=maxlen))
        print('Current total   : {:{ln}}   Current average : {:{ln}}'.format(sum_s, avg_s, ln=maxlen))
        print('Current median  : {:{ln}}   Current mode    : {:{ln}}'.format(med_s, mod_s, ln=maxlen))
        inp_s = input('Next number to add : ').strip()
        print('')
        try:
            inp = int(inp_s)
        except ValueError:
            continue
        inps.append(inp)
        cnt += 1
        if _min is None or inp < _min:
            _min = inp
        if _max is None or inp > _max:
            _max = inp
        if _sum is None:
            _sum = inp
        else:
            _sum += inp
        if inp in nums:
            cnts[nums[inp]].remove(inp)
            if len(cnts[nums[inp]]) == 0:
                cnts.pop(nums[inp])
                for i in cnt_heap:
                    if i.val == nums[inp]:
                        i.enabled = False
                while cnt_heap and cnt_heap[0].enabled == False:
                    heappop_max(cnt_heap)
            nums[inp] += 1
        else:
            nums[inp] = 1
        if nums[inp] in cnts:
            cnts[nums[inp]].add(inp)
        else:
            cnts[nums[inp]] = {inp}
            for i in cnt_heap:
                if i.val == nums[inp]:
                    i.enabled = True
                    break
            else:
                heappush_max(cnt_heap, Node(nums[inp]))
        if median is not None and inp <= median:
            if len(bot) > len(top):
                heappush_min(top, heapreplace_max(bot, inp))
            else:
                heappush_max(bot, inp)
        else:
            if len(top) > len(bot):
                heappush_max(bot, heapreplace_min(top, inp))
            else:
                heappush_min(top, inp)
    else:
        if len(top) == 0 and len(bot) == 0:
            median = None
        elif len(top) < len(bot):
            median = bot[0]
        elif len(top) > len(bot):
            median = top[0]
        else:
            median = (bot[0]+top[0]) / 2 if (bot[0]&1 + top[0]&1) & 1 else round((bot[0]+top[0]) / 2)
        if len(cnts) == 0:
            mode = None
        else:
            mode = ', '.join(str(i) for i in cnts[cnt_heap[0].val])
        min_s = str(_min)
        max_s = str(_max)
        sum_s = str(_sum)
        avg_s = str(round(_sum/cnt, 4) if cnt else None)
        med_s = str(median)
        mod_s = str(mode)
        maxlen = max(len(min_s), len(max_s), len(sum_s), len(avg_s), len(med_s))
        print('Final numbers: {}'.format(inps))
        print('Minimum : {:{ln}}   Maximum : {:{ln}}'.format(min_s, max_s, ln=maxlen))
        print('Total   : {:{ln}}   Average : {:{ln}}'.format(sum_s, avg_s, ln=maxlen))
        print('Median  : {:{ln}}   Mode    : {:{ln}}'.format(med_s, mod_s, ln=maxlen))


if __name__ == '__main__':
    main()
