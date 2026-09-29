import {
  DesktopWidgetOccurrence,
  DesktopWidgetSnapshot,
  parseDesktopWidgetSnapshot,
  todayEast8Date,
} from './DesktopWidgetSnapshotStore';
import { openTodaySchedule } from './DesktopWidgetCardActions';

@Entry
@Component
struct TodayScheduleWidgetCard {
  @LocalStorageProp('snapshot') private snapshotText: string = '';
  @LocalStorageProp('snapshotAvailable') private snapshotAvailable: boolean = false;
  @LocalStorageProp('formDimension') private formDimension: number = 2;

  build() {
    Column() {
      if (this.snapshot()?.schedule.status === 'ready' && this.todaysCourses().length === 0) {
        Text('今天没有课了~')
          .fontSize(this.formDimension === 2 ? 13 : 16)
          .fontColor($r('app.color.widget_on_surface_variant'))
          .width('100%')
          .height('100%')
          .textAlign(TextAlign.Center)
      } else {
        Row() {
          Text(this.weekLabel())
            .fontSize(this.formDimension === 2 ? 12 : 14)
            .fontWeight(500)
            .fontColor($r('app.color.widget_on_surface'))
          Blank()
          if (this.snapshot()?.schedule.status === 'ready') {
            Text(`${this.todaysCourses().length}节课`)
              .fontSize(this.formDimension === 2 ? 11 : 12)
              .fontColor($r('app.color.widget_on_surface_variant'))
          }
        }
        .width('100%')
        .margin({ bottom: this.formDimension === 2 ? 6 : 8 })

        if (this.snapshot()?.schedule.status === 'ready') {
          Column() {
              ForEach(
                this.todaysCourses().slice(0, this.formDimension === 2 ? 2 : 4),
                (course: DesktopWidgetOccurrence) => {
                  Row() {
                    Column()
                      .width(3)
                      .height(this.formDimension === 2 ? 30 : 36)
                      .backgroundColor($r('app.color.widget_primary'))
                      .borderRadius(2)
                    Column() {
                      Text(course.courseName)
                        .fontSize(this.formDimension === 2 ? 12 : 14)
                        .fontWeight(500)
                        .fontColor($r('app.color.widget_on_surface'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row() {
                        if (course.location.length > 0) {
                          Text(course.location)
                            .layoutWeight(1)
                            .fontSize(this.formDimension === 2 ? 10 : 11)
                            .fontColor($r('app.color.widget_on_surface_variant'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                        Text(this.timeLabel(course))
                          .fontSize(this.formDimension === 2 ? 10 : 11)
                          .fontColor($r('app.color.widget_on_surface_variant'))
                          .maxLines(1)
                      }
                      .width('100%')
                    }
                    .layoutWeight(1)
                    .margin({ left: this.formDimension === 2 ? 8 : 10 })
                  }
                  .height(this.formDimension === 2 ? 40 : 48)
                  .width('100%')
                },
                (course: DesktopWidgetOccurrence) => course.id,
              )
          }
          .width('100%')
        } else {
          Text(this.statusMessage())
            .width('100%')
            .fontSize(this.formDimension === 2 ? 12 : 14)
            .fontColor($r('app.color.widget_on_surface_variant'))
            .maxLines(2)
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.formDimension === 2 ? 10 : 16,
      right: this.formDimension === 2 ? 10 : 16,
      top: 5,
      bottom: 5,
    })
    .backgroundColor($r('app.color.widget_surface'))
    .borderRadius(20)
    .onClick(() => openTodaySchedule(this))
  }

  private snapshot(): DesktopWidgetSnapshot | null {
    if (!this.snapshotAvailable) return null;
    return parseDesktopWidgetSnapshot(this.snapshotText);
  }

  private weekLabel(): string {
    const week = this.snapshot()?.schedule.currentWeek;
    return week === undefined || week === null ? '第—周' : `第${week}周`;
  }

  private statusMessage(): string {
    const status = this.snapshot()?.schedule.status;
    if (status === 'signedOut') return '登录后显示今日课表';
    if (status === 'noSchedule') return '暂无课表，打开 MyCHU 获取';
    if (status === 'calendarUnavailable') return '课表日期信息暂不可用';
    return '打开 MyCHU 同步今日课表';
  }

  private todaysCourses(): Array<DesktopWidgetOccurrence> {
    const snapshot = this.snapshot();
    if (snapshot === null || snapshot.schedule.status !== 'ready') return [];
    const today = todayEast8Date();
    const now = Date.now();
    return snapshot.schedule.occurrences.filter((course) => {
      if (course.date !== today) return false;
      if (course.endTime === null) return true;
      const endAt = Date.parse(`${course.date}T${course.endTime}:00+08:00`);
      return isNaN(endAt) || endAt > now;
    }).sort((first, second) =>
      first.startPeriod - second.startPeriod ||
      first.endPeriod - second.endPeriod ||
      first.courseName.localeCompare(second.courseName));
  }

  private timeLabel(course: DesktopWidgetOccurrence): string {
    if (course.startTime !== null && course.endTime !== null) {
      return `${course.startTime}–${course.endTime}`;
    }
    return course.periodLabel;
  }
}
