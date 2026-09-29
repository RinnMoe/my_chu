/*
* Copyright (c) 2024 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

@Component
struct OhosPromptView {
  textValue: string | null = null
  message: string | null = null
  cancelButton: string | null = null
  confirmButton: string | null = null
  cancel: Function | null = null;
  confirm: Function | null = null;

  aboutToAppear(): void {

  }

  build() {
    Column() {
      Text(this.message).fontSize(20).margin({ top: 10, bottom: 10 })
      TextInput({ placeholder: '', text: this.textValue }).height(60).width('90%')
        .onChange((value: string) => {
          this.textValue = value
        })
      Flex({ justifyContent: FlexAlign.SpaceAround }) {
        Button(this.cancelButton != null && this.cancelButton.length > 0 ? this.cancelButton : "取消")
          .onClick(() => {
            if (this.cancel) {
              this.cancel()
            }
          }).fontColor(Color.Black)
        Button(this.confirmButton != null && this.confirmButton.length > 0 ? this.confirmButton : "确定")
          .onClick(() => {
            if (this.confirm) {
              this.confirm(this.textValue)
            }
          })
      }.margin({ top: 10, bottom: 10 })
    }.borderRadius(10)
  }
}

@Builder
export function ohosPromptDialogBuilder(textValue: string | null,
                                        message: string | null,
                                        cancelButton: string | null,
                                        confirmButton: string | null,
                                        cancel: Function, confirm: Function) {
  OhosPromptView({
    textValue: textValue,
    message: message,
    cancelButton: cancelButton,
    confirmButton: confirmButton,
    cancel: cancel,
    confirm: confirm
  })
}
