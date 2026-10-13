import { parseDesktopWidgetSnapshot, SCHEDULE_TARGET_ID } from './DesktopWidgetSnapshotStore';
import { openDesktopWidgetTarget } from './DesktopWidgetCardActions';
import { projectWidgetWeek, weekDateAt, weekCourseColorIndex, WeekCourseSlot, WeekScheduleData } from './WeekScheduleWidgetData';

@Entry
@Component
struct WeekScheduleWidgetCard {
  @LocalStorageProp('snapshot') private snapshotText: string = '';
  @LocalStorageProp('snapshotAvailable') private snapshotAvailable: boolean = false;
  @LocalStorageProp('renderedAt') private renderedAt: number = Date.now();

  private data(): WeekScheduleData {
    return projectWidgetWeek(this.snapshotAvailable ? parseDesktopWidgetSnapshot(this.snapshotText) : null, this.renderedAt);
  }

  private emptyMessage(): string {
    const status = this.data().status;
    if (status === 'signedOut') return '登录后显示周课表';
    if (status === 'noSchedule') return '暂无课表，打开 MyCHU 获取';
    if (status === 'calendarUnavailable') return '课表日期信息暂不可用';
    if (status === 'outsideTerm') return '当前不在教学周';
    if (status === 'ready') return '本周暂无课程';
    return '打开 MyCHU 同步周课表';
  }

  private hasCourses(): boolean {
    return this.data().days.some((slots: Array<WeekCourseSlot>) =>
      slots.some((slot: WeekCourseSlot) => slot.courses.length > 0));
  }

  private courseColor(slot: WeekCourseSlot): Resource {
    const index = weekCourseColorIndex(slot.courses[0].courseName);
    if (index === 0) return $r('app.color.widget_course_0');
    if (index === 1) return $r('app.color.widget_course_1');
    if (index === 2) return $r('app.color.widget_course_2');
    if (index === 3) return $r('app.color.widget_course_3');
    if (index === 4) return $r('app.color.widget_course_4');
    return $r('app.color.widget_course_5');
  }

  // A spanning block includes the same internal section gaps as the period axis.
  private slotWeight(slot: WeekCourseSlot): number {
    let weight = slot.endPeriod - slot.startPeriod + 1;
    if (slot.startPeriod <= 4 && slot.endPeriod > 4) weight += 0.15;
    if (slot.startPeriod <= 8 && slot.endPeriod > 8) weight += 0.15;
    return weight;
  }

  build() {
    Column() {
      Row() {
        Text('周课表').fontSize(14).fontWeight(600).fontColor($r('app.color.widget_on_surface'))
        Blank()
        Text(this.data().currentWeek === null ? '' : `第${this.data().currentWeek}周`)
          .fontSize(12).fontColor($r('app.color.widget_primary'))
      }.width('100%').height(24)
      Text(`${this.data().weekStart.slice(5).replace('-', '/')}—${weekDateAt(this.data().weekStart, 6).slice(5).replace('-', '/')}`)
        .fontSize(10).fontColor($r('app.color.widget_on_surface_variant')).width('100%').height(18)
      if (this.data().status !== 'ready' || !this.hasCourses()) {
        Text(this.emptyMessage()).fontSize(14).fontColor($r('app.color.widget_on_surface_variant'))
          .width('100%').layoutWeight(1).textAlign(TextAlign.Center)
      } else {
        Row() {
          Blank().width(18)
          ForEach([0, 1, 2, 3, 4, 5, 6], (day: number) => {
            Text(`${['一', '二', '三', '四', '五', '六', '日'][day]} ${Number(weekDateAt(this.data().weekStart, day).slice(8))}`)
              .fontSize(10).maxLines(1).layoutWeight(1).textAlign(TextAlign.Center)
              .fontColor(weekDateAt(this.data().weekStart, day) === this.data().today ?
                $r('app.color.widget_primary') : $r('app.color.widget_on_surface_variant'))
              .fontWeight(weekDateAt(this.data().weekStart, day) === this.data().today ? 600 : 400)
          })
        }.width('100%').height(16)
        Row() {
          Column() {
            ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], (period: number) => {
              Text(`${period}`).fontSize(10).fontColor($r('app.color.widget_on_surface_variant'))
                .width('100%').layoutWeight(1).textAlign(TextAlign.Center)
              if (period === 4 || period === 8) {
                Blank().layoutWeight(0.15)
              }
            })
          }.width(18).height('100%')
          ForEach([0, 1, 2, 3, 4, 5, 6], (day: number) => {
            Column() {
              ForEach(this.data().days[day], (slot: WeekCourseSlot) => {
                if (slot.courses.length === 0) {
                  Blank().layoutWeight(this.slotWeight(slot))
                } else {
                  Column() {
                    Row() {
                      Text(slot.courses[0].courseName)
                        .fontSize(10).fontWeight(500).fontColor($r('app.color.widget_course_text'))
                        .maxLines(slot.endPeriod > slot.startPeriod ? 2 : 1).layoutWeight(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (slot.courses.length > 1) {
                        Text(`＋${slot.courses.length - 1}`).fontSize(9)
                          .fontColor($r('app.color.widget_course_text')).maxLines(1)
                      }
                    }.width('100%')
                    if (slot.endPeriod - slot.startPeriod >= 2 && slot.courses[0].location.length > 0) {
                      Text(slot.courses[0].location).fontSize(9).fontColor($r('app.color.widget_course_text'))
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }.width('100%').layoutWeight(this.slotWeight(slot))
                    .padding(2).backgroundColor(this.courseColor(slot)).borderRadius(4).clip(true)
                    .justifyContent(FlexAlign.Center)
                }
                if (slot.endPeriod === 4 || slot.endPeriod === 8) {
                  Blank().layoutWeight(0.15)
                }
              }, (slot: WeekCourseSlot) => `${day}-${slot.startPeriod}`)
            }.layoutWeight(1).height('100%').margin({ left: 1, right: 1 })
          })
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').padding(10)
      .backgroundColor($r('app.color.widget_surface')).borderRadius(20)
      .onClick(() => openDesktopWidgetTarget(this, SCHEDULE_TARGET_ID))
  }
}
