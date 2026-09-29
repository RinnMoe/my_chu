import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import {
  createDesktopWidgetFormData,
  getDesktopWidgetFormRegistration,
  registerDesktopWidgetForm,
  removeDesktopWidgetForm,
  TODAY_SCHEDULE_FORM,
} from './DesktopWidgetSnapshotStore';

export default class DesktopWidgetFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const parameters = want.parameters;
    const rawId = parameters?.[formInfo.FormParam.IDENTITY_KEY];
    const rawDimension = parameters?.[formInfo.FormParam.DIMENSION_KEY];
    const formId = typeof rawId === 'string' ? rawId : '';
    const dimension = typeof rawDimension === 'number' ? rawDimension : 2;

    if (formId.length > 0) {
      try {
        registerDesktopWidgetForm(this.context.filesDir, {
          formId: formId,
          formName: TODAY_SCHEDULE_FORM,
          dimension: dimension,
        });
      } catch (_) {
        // The form still renders its initial local state if registry persistence fails.
      }
    }
    return createDesktopWidgetFormData(
      this.context.filesDir,
      TODAY_SCHEDULE_FORM,
      dimension,
    );
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    let registration = getDesktopWidgetFormRegistration(
      this.context.filesDir,
      formId,
    );
    if (registration === null) return;

    const dimensionKey = formInfo.FormParam.DIMENSION_KEY;
    const requestedDimension = wantParams?.[dimensionKey];
    if (typeof requestedDimension === 'number' &&
      requestedDimension !== registration.dimension) {
      registration = {
        formId: registration.formId,
        formName: registration.formName,
        dimension: requestedDimension,
      };
      try {
        registerDesktopWidgetForm(this.context.filesDir, registration);
      } catch (_) {
        // A resize still receives the latest snapshot even if its size cannot be saved.
      }
    }

    const data = createDesktopWidgetFormData(
      this.context.filesDir,
      registration.formName,
      registration.dimension,
    );
    formProvider.updateForm(formId, data).catch(() => {});
  }

  onRemoveForm(formId: string): void {
    try {
      removeDesktopWidgetForm(this.context.filesDir, formId);
    } catch (_) {
      // A stale form ID is ignored; the registry is only used for best-effort refresh.
    }
  }
}
